#==============================================================================
# Vault Enterprise - Custom Terraform Configuration (HVD Architecture)
#==============================================================================
# This configuration deploys Vault Enterprise on AWS following HashiCorp
# Validated Design principles without relying on the external module.

#==============================================================================
# Secrets Manager - Store TLS Certificates (avoids user_data size limits)
#==============================================================================

resource "aws_secretsmanager_secret" "vault_tls_certs" {
  name                    = "${var.resource_name_prefix}-vault-tls-certs"
  description             = "Vault TLS certificates for ${var.resource_name_prefix}"
  recovery_window_in_days = 0

  tags = merge(var.resource_tags, { Name = "${var.resource_name_prefix}-vault-tls-certs" })
}

resource "aws_secretsmanager_secret_version" "vault_tls_certs" {
  secret_id = aws_secretsmanager_secret.vault_tls_certs.id
  secret_string = jsonencode({
    server_cert = local.vault_server_cert
    server_key  = local.vault_server_key
    ca_cert     = local.vault_ca_cert
  })
}

resource "aws_secretsmanager_secret" "vault_license" {
  name                    = "${var.resource_name_prefix}-vault-license"
  description             = "Vault Enterprise license for ${var.resource_name_prefix}"
  recovery_window_in_days = 0

  tags = merge(var.resource_tags, { Name = "${var.resource_name_prefix}-vault-license" })
}

resource "aws_secretsmanager_secret_version" "vault_license" {
  secret_id = aws_secretsmanager_secret.vault_license.id
  secret_string = jsonencode({
    license = local.vault_license
  })
}

#==============================================================================
# Security Groups
#==============================================================================

resource "aws_security_group" "vault_nodes" {
  name        = "${var.resource_name_prefix}-vault-nodes"
  description = "Security group for Vault Enterprise nodes"
  vpc_id      = local.effective_vpc_id
  tags        = merge(var.resource_tags, { Name = "${var.resource_name_prefix}-vault-nodes" })
}

# Vault cluster peer communication
resource "aws_vpc_security_group_ingress_rule" "vault_cluster" {
  security_group_id = aws_security_group.vault_nodes.id

  description                  = "Vault cluster peer communication"
  from_port                    = 8201
  to_port                      = 8201
  ip_protocol                  = "tcp"
  referenced_security_group_id = aws_security_group.vault_nodes.id

  tags = { Name = "${var.resource_name_prefix}-vault-cluster" }
}

# Vault API from load balancer
resource "aws_vpc_security_group_ingress_rule" "vault_api_from_lb" {
  security_group_id = aws_security_group.vault_nodes.id

  description                  = "Vault API from load balancer"
  from_port                    = 8200
  to_port                      = 8200
  ip_protocol                  = "tcp"
  referenced_security_group_id = aws_security_group.vault_lb.id

  tags = { Name = "${var.resource_name_prefix}-vault-api-from-lb" }
}

# SSH (optional, for debugging)
resource "aws_vpc_security_group_ingress_rule" "vault_ssh" {
  count = length(var.ssh_cidr_blocks) > 0 ? 1 : 0

  security_group_id = aws_security_group.vault_nodes.id

  description = "SSH access to Vault nodes"
  from_port   = 22
  to_port     = 22
  ip_protocol = "tcp"
  cidr_ipv4   = var.ssh_cidr_blocks[0]

  tags = { Name = "${var.resource_name_prefix}-vault-ssh" }
}

# Egress: allow all outbound
resource "aws_vpc_security_group_egress_rule" "vault_egress" {
  security_group_id = aws_security_group.vault_nodes.id

  description = "Allow all outbound traffic"
  cidr_ipv4   = "0.0.0.0/0"
  ip_protocol = "-1"

  tags = { Name = "${var.resource_name_prefix}-vault-egress" }
}

resource "aws_security_group" "vault_lb" {
  name        = "${var.resource_name_prefix}-vault-lb"
  description = "Security group for Vault load balancer"
  vpc_id      = local.effective_vpc_id
  tags        = merge(var.resource_tags, { Name = "${var.resource_name_prefix}-vault-lb" })
}

# Allow API access to LB from specified CIDR blocks
resource "aws_vpc_security_group_ingress_rule" "lb_api" {
  count = length(var.vault_api_cidr_blocks) > 0 ? 1 : 0

  security_group_id = aws_security_group.vault_lb.id

  description = "Vault API access"
  from_port   = 8200
  to_port     = 8200
  ip_protocol = "tcp"
  cidr_ipv4   = var.vault_api_cidr_blocks[0]

  tags = { Name = "${var.resource_name_prefix}-lb-api" }
}

# LB egress to vault nodes
resource "aws_vpc_security_group_egress_rule" "lb_to_vault" {
  security_group_id = aws_security_group.vault_lb.id

  description                  = "LB to Vault nodes"
  from_port                    = 8200
  to_port                      = 8200
  ip_protocol                  = "tcp"
  referenced_security_group_id = aws_security_group.vault_nodes.id

  tags = { Name = "${var.resource_name_prefix}-lb-to-vault" }
}

#==============================================================================
# IAM Roles and Policies
#==============================================================================

resource "aws_iam_role" "vault" {
  name               = "${var.resource_name_prefix}-vault-role"
  assume_role_policy = data.aws_iam_policy_document.vault_assume_role.json
  tags               = var.resource_tags
}

data "aws_iam_policy_document" "vault_assume_role" {
  statement {
    actions = ["sts:AssumeRole"]
    principals {
      type        = "Service"
      identifiers = ["ec2.amazonaws.com"]
    }
  }
}

resource "aws_iam_role_policy" "vault" {
  name   = "${var.resource_name_prefix}-vault-policy"
  role   = aws_iam_role.vault.id
  policy = data.aws_iam_policy_document.vault_policy.json
}

data "aws_iam_policy_document" "vault_policy" {
  # KMS auto-unseal
  statement {
    actions = [
      "kms:Encrypt",
      "kms:Decrypt",
      "kms:DescribeKey",
      "kms:GenerateRandom"
    ]
    resources = [local.effective_kms_key_arn]
  }

  # EC2 auto-join via Raft
  statement {
    actions = [
      "ec2:DescribeInstances",
      "ec2:DescribeVolumes",
      "ec2:DescribeTags"
    ]
    resources = ["*"]
  }

  # Secrets Manager for storing root token
  statement {
    actions = [
      "secretsmanager:CreateSecret",
      "secretsmanager:UpdateSecret",
      "secretsmanager:PutSecretValue"
    ]
    resources = ["arn:aws:secretsmanager:${var.aws_region}:*:secret:${var.resource_name_prefix}-vault-root-token*"]
  }

  # Secrets Manager for retrieving TLS certs and license
  statement {
    actions = [
      "secretsmanager:GetSecretValue",
      "secretsmanager:DescribeSecret"
    ]
    resources = [
      "arn:aws:secretsmanager:${var.aws_region}:*:secret:${var.resource_name_prefix}-vault-tls-certs*",
      "arn:aws:secretsmanager:${var.aws_region}:*:secret:${var.resource_name_prefix}-vault-license*"
    ]
  }
}

resource "aws_iam_instance_profile" "vault" {
  name = "${var.resource_name_prefix}-vault-profile"
  role = aws_iam_role.vault.name
}

#==============================================================================
# EC2 Launch Template
#==============================================================================

resource "aws_launch_template" "vault" {
  name_prefix   = "${var.resource_name_prefix}-"
  image_id      = data.aws_ami.ubuntu.id
  instance_type = var.instance_type

  iam_instance_profile {
    name = aws_iam_instance_profile.vault.name
  }

  user_data = base64encode(templatefile("${path.module}/user_data.sh", {
    vault_fqdn        = var.vault_fqdn
    kms_key_id        = local.effective_kms_key_arn
    node_count        = var.node_count
    vault_version     = var.vault_version
    resource_name_prefix = var.resource_name_prefix
    aws_region        = var.aws_region
    tls_secret_name   = aws_secretsmanager_secret.vault_tls_certs.name
    license_secret_name = aws_secretsmanager_secret.vault_license.name
  }))

  vpc_security_group_ids = [aws_security_group.vault_nodes.id]

  block_device_mappings {
    device_name = "/dev/sda1"
    ebs {
      volume_size           = 100
      volume_type           = "gp3"
      delete_on_termination = true
      encrypted             = true
    }
  }

  tag_specifications {
    resource_type = "instance"
    tags          = merge(var.resource_tags, { Name = "${var.resource_name_prefix}-vault" })
  }

  lifecycle {
    create_before_destroy = true
  }
}

# Get latest Ubuntu 22.04 LTS AMI
data "aws_ami" "ubuntu" {
  most_recent = true
  owners      = ["099720109477"] # Canonical

  filter {
    name   = "name"
    values = ["ubuntu/images/hvm-ssd/ubuntu-jammy-22.04-amd64-server-*"]
  }

  filter {
    name   = "virtualization-type"
    values = ["hvm"]
  }
}

#==============================================================================
# Auto Scaling Group
#==============================================================================

resource "aws_autoscaling_group" "vault" {
  name                = "${var.resource_name_prefix}-vault-asg"
  vpc_zone_identifier = local.effective_vault_subnets
  target_group_arns   = [aws_lb_target_group.vault.arn]

  min_size         = var.node_count
  max_size         = var.node_count
  desired_capacity = var.node_count

  health_check_type         = "ELB"
  health_check_grace_period = 300

  launch_template {
    id      = aws_launch_template.vault.id
    version = "$Latest"
  }

  # Ensure secrets are created before instances try to retrieve them
  depends_on = [
    aws_secretsmanager_secret_version.vault_tls_certs,
    aws_secretsmanager_secret_version.vault_license
  ]

  tag {
    key                 = "Name"
    value               = "${var.resource_name_prefix}-vault"
    propagate_at_launch = true
  }

  dynamic "tag" {
    for_each = var.resource_tags
    content {
      key                 = tag.key
      value               = tag.value
      propagate_at_launch = true
    }
  }

  lifecycle {
    create_before_destroy = true
  }
}

#==============================================================================
# Network Load Balancer
#==============================================================================

resource "aws_lb" "vault" {
  name               = "${var.resource_name_prefix}-vault-nlb"
  internal           = false
  load_balancer_type = "network"
  subnets            = local.effective_lb_subnets
  security_groups    = [aws_security_group.vault_lb.id]

  tags = merge(var.resource_tags, { Name = "${var.resource_name_prefix}-vault-nlb" })
}

resource "aws_lb_target_group" "vault" {
  name        = "${var.resource_name_prefix}-vault"
  port        = 8200
  protocol    = "TCP"
  vpc_id      = local.effective_vpc_id
  target_type = "instance"

  health_check {
    healthy_threshold   = 2
    unhealthy_threshold = 2
    interval            = 10
    port                = "8200"
    protocol            = "TCP"
  }

  tags = var.resource_tags
}

resource "aws_lb_listener" "vault" {
  load_balancer_arn = aws_lb.vault.arn
  port              = 8200
  protocol          = "TCP"

  default_action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.vault.arn
  }
}

#==============================================================================
# Outputs
#==============================================================================

output "vault_load_balancer_dns" {
  value       = aws_lb.vault.dns_name
  description = "DNS name of the Vault load balancer"
}

output "vault_cli_config" {
  value       = "export VAULT_ADDR=https://${aws_lb.vault.dns_name}:8200\nexport VAULT_TOKEN=<your-token>\nexport VAULT_NAMESPACE=admin"
  description = "Suggested environment variables to configure the Vault CLI"
  sensitive   = true
}
