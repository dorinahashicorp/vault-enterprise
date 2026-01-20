################################################################################
# AWS Infrastructure Prerequisites for Vault Enterprise
################################################################################

locals {
  availability_zones = slice(data.aws_availability_zones.available.names, 0, 3)

  vpc_cidr           = var.vpc_cidr
  private_subnets    = [for i, az in local.availability_zones : cidrsubnet(local.vpc_cidr, 4, i)]
  public_subnets     = [for i, az in local.availability_zones : cidrsubnet(local.vpc_cidr, 4, i + 3)]
}

################################################################################
# Data Sources
################################################################################

data "aws_availability_zones" "available" {
  state = "available"

  filter {
    name   = "opt-in-status"
    values = ["opt-in-not-required"]
  }
}

################################################################################
# VPC
################################################################################

resource "aws_vpc" "vault" {
  cidr_block           = local.vpc_cidr
  enable_dns_hostnames = true
  enable_dns_support   = true

  tags = {
    Name = "${var.resource_name_prefix}-vault-vpc"
  }
}

################################################################################
# Internet Gateway (for NAT Gateway)
################################################################################

resource "aws_internet_gateway" "vault" {
  vpc_id = aws_vpc.vault.id

  tags = {
    Name = "${var.resource_name_prefix}-vault-igw"
  }
}

################################################################################
# Public Subnets (for NAT Gateways and Load Balancer if external)
################################################################################

resource "aws_subnet" "public" {
  count             = length(local.availability_zones)
  vpc_id            = aws_vpc.vault.id
  cidr_block        = local.public_subnets[count.index]
  availability_zone = local.availability_zones[count.index]

  map_public_ip_on_launch = true

  tags = {
    Name = "${var.resource_name_prefix}-vault-public-${local.availability_zones[count.index]}"
    Tier = "public"
  }
}

################################################################################
# Private Subnets (for Vault nodes)
################################################################################

resource "aws_subnet" "private" {
  count             = length(local.availability_zones)
  vpc_id            = aws_vpc.vault.id
  cidr_block        = local.private_subnets[count.index]
  availability_zone = local.availability_zones[count.index]

  tags = {
    Name = "${var.resource_name_prefix}-vault-private-${local.availability_zones[count.index]}"
    Tier = "private"
  }
}

################################################################################
# Elastic IPs for NAT Gateways
################################################################################

resource "aws_eip" "nat" {
  count  = length(local.availability_zones)
  domain = "vpc"

  tags = {
    Name = "${var.resource_name_prefix}-vault-nat-eip-${local.availability_zones[count.index]}"
  }

  depends_on = [aws_internet_gateway.vault]
}

################################################################################
# NAT Gateways (one per AZ for high availability)
################################################################################

resource "aws_nat_gateway" "vault" {
  count         = length(local.availability_zones)
  allocation_id = aws_eip.nat[count.index].id
  subnet_id     = aws_subnet.public[count.index].id

  tags = {
    Name = "${var.resource_name_prefix}-vault-nat-${local.availability_zones[count.index]}"
  }

  depends_on = [aws_internet_gateway.vault]
}

################################################################################
# Public Route Table
################################################################################

resource "aws_route_table" "public" {
  vpc_id = aws_vpc.vault.id

  route {
    cidr_block = "0.0.0.0/0"
    gateway_id = aws_internet_gateway.vault.id
  }

  tags = {
    Name = "${var.resource_name_prefix}-vault-public-rt"
  }
}

resource "aws_route_table_association" "public" {
  count          = length(local.availability_zones)
  subnet_id      = aws_subnet.public[count.index].id
  route_table_id = aws_route_table.public.id
}

################################################################################
# Private Route Tables (one per AZ for NAT Gateway redundancy)
################################################################################

resource "aws_route_table" "private" {
  count  = length(local.availability_zones)
  vpc_id = aws_vpc.vault.id

  route {
    cidr_block     = "0.0.0.0/0"
    nat_gateway_id = aws_nat_gateway.vault[count.index].id
  }

  tags = {
    Name = "${var.resource_name_prefix}-vault-private-rt-${local.availability_zones[count.index]}"
  }
}

resource "aws_route_table_association" "private" {
  count          = length(local.availability_zones)
  subnet_id      = aws_subnet.private[count.index].id
  route_table_id = aws_route_table.private[count.index].id
}

################################################################################
# VPC Endpoints for AWS Services (reduce NAT Gateway costs)
################################################################################

# S3 Gateway Endpoint (free)
resource "aws_vpc_endpoint" "s3" {
  vpc_id       = aws_vpc.vault.id
  service_name = "com.amazonaws.${var.aws_region}.s3"

  tags = {
    Name = "${var.resource_name_prefix}-vault-s3-endpoint"
  }
}

resource "aws_vpc_endpoint_route_table_association" "s3_private" {
  count           = length(local.availability_zones)
  route_table_id  = aws_route_table.private[count.index].id
  vpc_endpoint_id = aws_vpc_endpoint.s3.id
}

# Secrets Manager Interface Endpoint (reduces NAT costs for secret retrieval)
resource "aws_vpc_endpoint" "secretsmanager" {
  vpc_id              = aws_vpc.vault.id
  service_name        = "com.amazonaws.${var.aws_region}.secretsmanager"
  vpc_endpoint_type   = "Interface"
  subnet_ids          = aws_subnet.private[*].id
  security_group_ids  = [aws_security_group.vpc_endpoints.id]
  private_dns_enabled = true

  tags = {
    Name = "${var.resource_name_prefix}-vault-secretsmanager-endpoint"
  }
}

# KMS Interface Endpoint (reduces NAT costs for auto-unseal)
resource "aws_vpc_endpoint" "kms" {
  vpc_id              = aws_vpc.vault.id
  service_name        = "com.amazonaws.${var.aws_region}.kms"
  vpc_endpoint_type   = "Interface"
  subnet_ids          = aws_subnet.private[*].id
  security_group_ids  = [aws_security_group.vpc_endpoints.id]
  private_dns_enabled = true

  tags = {
    Name = "${var.resource_name_prefix}-vault-kms-endpoint"
  }
}

# EC2 Interface Endpoint (for auto-join)
resource "aws_vpc_endpoint" "ec2" {
  vpc_id              = aws_vpc.vault.id
  service_name        = "com.amazonaws.${var.aws_region}.ec2"
  vpc_endpoint_type   = "Interface"
  subnet_ids          = aws_subnet.private[*].id
  security_group_ids  = [aws_security_group.vpc_endpoints.id]
  private_dns_enabled = true

  tags = {
    Name = "${var.resource_name_prefix}-vault-ec2-endpoint"
  }
}

################################################################################
# Security Group for VPC Endpoints
################################################################################

resource "aws_security_group" "vpc_endpoints" {
  name        = "${var.resource_name_prefix}-vault-vpc-endpoints-sg"
  description = "Security group for VPC endpoints"
  vpc_id      = aws_vpc.vault.id

  ingress {
    description = "HTTPS from VPC"
    from_port   = 443
    to_port     = 443
    protocol    = "tcp"
    cidr_blocks = [local.vpc_cidr]
  }

  egress {
    description = "Allow all outbound"
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = {
    Name = "${var.resource_name_prefix}-vault-vpc-endpoints-sg"
  }
}

################################################################################
# KMS Key for Vault Auto-Unseal
################################################################################

resource "aws_kms_key" "vault_unseal" {
  description             = "KMS key for Vault auto-unseal"
  deletion_window_in_days = var.kms_deletion_window
  enable_key_rotation     = true

  tags = {
    Name    = "${var.resource_name_prefix}-vault-unseal-key"
    Purpose = "VaultAutoUnseal"
  }
}

resource "aws_kms_alias" "vault_unseal" {
  name          = "alias/${var.resource_name_prefix}-vault-unseal"
  target_key_id = aws_kms_key.vault_unseal.key_id
}

################################################################################
# Outputs for use in main Vault module
################################################################################

output "vpc_id" {
  description = "VPC ID"
  value       = aws_vpc.vault.id
}

output "private_subnet_ids" {
  description = "Private subnet IDs for Vault nodes"
  value       = aws_subnet.private[*].id
}

output "public_subnet_ids" {
  description = "Public subnet IDs for load balancer"
  value       = aws_subnet.public[*].id
}

output "kms_key_arn" {
  description = "KMS key ARN for Vault auto-unseal"
  value       = aws_kms_key.vault_unseal.arn
}

output "availability_zones" {
  description = "Availability zones used"
  value       = local.availability_zones
}
