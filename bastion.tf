################################################################################
# Bastion Host for Vault Access
################################################################################
# Temporary bastion host in public subnet for accessing internal Vault cluster
# Can be removed after Vault initialization and testing

# Data source for latest Amazon Linux 2023 AMI
data "aws_ami" "amazon_linux_2023" {
  most_recent = true
  owners      = ["amazon"]

  filter {
    name   = "name"
    values = ["al2023-ami-*-x86_64"]
  }

  filter {
    name   = "virtualization-type"
    values = ["hvm"]
  }
}

# Security Group for Bastion Host
resource "aws_security_group" "bastion" {
  name        = "${var.resource_name_prefix}-bastion-sg"
  description = "Security group for bastion host - SSH access"
  vpc_id      = aws_vpc.vault.id

  # SSH from internet (you can restrict this to your IP)
  ingress {
    description = "SSH from internet"
    from_port   = 22
    to_port     = 22
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"] # Consider restricting to your IP for better security
  }

  # Allow all outbound traffic
  egress {
    description = "Allow all outbound"
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = {
    Name = "${var.resource_name_prefix}-bastion-sg"
  }
}

# IAM Role for Bastion Host (minimal permissions)
resource "aws_iam_role" "bastion" {
  name = "${var.resource_name_prefix}-bastion-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Action = "sts:AssumeRole"
        Effect = "Allow"
        Principal = {
          Service = "ec2.amazonaws.com"
        }
      }
    ]
  })

  tags = {
    Name = "${var.resource_name_prefix}-bastion-role"
  }
}

# Attach SSM policy for Session Manager access (optional alternative to SSH)
resource "aws_iam_role_policy_attachment" "bastion_ssm" {
  role       = aws_iam_role.bastion.name
  policy_arn = "arn:aws:iam::aws:policy/AmazonSSMManagedInstanceCore"
}

# IAM Instance Profile
resource "aws_iam_instance_profile" "bastion" {
  name = "${var.resource_name_prefix}-bastion-profile"
  role = aws_iam_role.bastion.name
}

# Bastion EC2 Instance
resource "aws_instance" "bastion" {
  ami                    = data.aws_ami.amazon_linux_2023.id
  instance_type          = "t3.micro"
  subnet_id              = aws_subnet.public[0].id
  vpc_security_group_ids = [aws_security_group.bastion.id]
  iam_instance_profile   = aws_iam_instance_profile.bastion.name

  # Public IP for SSH access
  associate_public_ip_address = true

  # User data to install Vault CLI
  user_data = base64encode(<<-EOF
    #!/bin/bash
    set -e

    # Install Vault CLI
    yum install -y yum-utils
    yum-config-manager --add-repo https://rpm.releases.hashicorp.com/AmazonLinux/hashicorp.repo
    yum -y install vault-enterprise

    # Install useful tools
    yum install -y jq curl

    # Set VAULT_ADDR for convenience
    echo "export VAULT_ADDR=https://${var.vault_fqdn}:8200" >> /etc/profile.d/vault.sh
    echo "export VAULT_SKIP_VERIFY=1" >> /etc/profile.d/vault.sh

    echo "Bastion host ready! Use 'vault status' to check Vault cluster."
  EOF
  )

  tags = {
    Name = "${var.resource_name_prefix}-bastion"
  }

  # Generate SSH key automatically or use existing one
  # For now, you'll need to add your SSH key manually or use Session Manager
}

################################################################################
# Outputs
################################################################################

output "bastion_public_ip" {
  description = "Public IP address of bastion host"
  value       = aws_instance.bastion.public_ip
}

output "bastion_connection_command" {
  description = "Command to connect to bastion via SSH"
  value       = "ssh -i ~/.ssh/your-key.pem ec2-user@${aws_instance.bastion.public_ip}"
}

output "bastion_ssm_command" {
  description = "Command to connect to bastion via Session Manager"
  value       = "aws ssm start-session --target ${aws_instance.bastion.id} --region ${var.aws_region}"
}

output "vault_connection_from_bastion" {
  description = "Commands to run on bastion to connect to Vault"
  value = <<-EOT
    # Set Vault address (already configured in /etc/profile.d/vault.sh)
    export VAULT_ADDR=https://${var.vault_fqdn}:8200
    export VAULT_SKIP_VERIFY=1

    # Check Vault status
    vault status

    # Initialize Vault (if not already initialized)
    vault operator init
  EOT
}
