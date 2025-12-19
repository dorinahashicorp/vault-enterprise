#==============================================================================
# AWS Prerequisites for Vault Enterprise HVD
#==============================================================================
# This configuration creates the foundational AWS resources required by the
# HVD module. You should run this FIRST, before running the main Vault module.
#
# Created resources:
# - VPC with 3 private subnets and 3 public subnets (one per AZ)
# - Internet Gateway and NAT Gateways for internet access
# - Route tables for public/private subnets
# - KMS key for Vault auto-unseal
#
# Prerequisites (done OUTSIDE Terraform before running terraform apply):
# 1. Create 4 Secrets Manager secrets in AWS with actual content:
#    - vault-license (Vault Enterprise license file)
#    - vault-tls-cert (TLS certificate in PEM format)
#    - vault-tls-key (TLS private key in PEM format)
#    - vault-ca-cert (CA certificate in PEM format)
# 2. Note the ARNs of these secrets
# 3. Provide the ARNs as variables when running terraform apply
#
# See: AWS_SETUP_STEPS.md for AWS CLI commands to create secrets

terraform {
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
  }
}

provider "aws" {
  region = var.aws_region
}

#==============================================================================
# Data Sources
#==============================================================================

data "aws_availability_zones" "available" {
  state = "available"
}

#==============================================================================
# VPC
#==============================================================================

resource "aws_vpc" "main" {
  cidr_block           = var.vpc_cidr
  enable_dns_hostnames = true
  enable_dns_support   = true

  tags = merge(var.resource_tags, {
    Name = "${var.friendly_name_prefix}-vpc"
  })
}

#==============================================================================
# Internet Gateway
#==============================================================================

resource "aws_internet_gateway" "main" {
  vpc_id = aws_vpc.main.id

  tags = merge(var.resource_tags, {
    Name = "${var.friendly_name_prefix}-igw"
  })
}

#==============================================================================
# Public Subnets (for Load Balancer and NAT Gateway)
#==============================================================================

resource "aws_subnet" "public" {
  count                   = 3
  vpc_id                  = aws_vpc.main.id
  cidr_block              = cidrsubnet(var.vpc_cidr, 3, count.index)
  availability_zone       = data.aws_availability_zones.available.names[count.index]
  map_public_ip_on_launch = true

  tags = merge(var.resource_tags, {
    Name = "${var.friendly_name_prefix}-public-subnet-${count.index + 1}"
    Type = "Public"
  })
}

#==============================================================================
# Private Subnets (for Vault EC2 Instances)
#==============================================================================

resource "aws_subnet" "private" {
  count              = 3
  vpc_id             = aws_vpc.main.id
  cidr_block         = cidrsubnet(var.vpc_cidr, 3, count.index + 3)
  availability_zone  = data.aws_availability_zones.available.names[count.index]

  tags = merge(var.resource_tags, {
    Name = "${var.friendly_name_prefix}-private-subnet-${count.index + 1}"
    Type = "Private"
  })
}

#==============================================================================
# Elastic IPs for NAT Gateways
#==============================================================================

resource "aws_eip" "nat" {
  count  = 3
  domain = "vpc"

  tags = merge(var.resource_tags, {
    Name = "${var.friendly_name_prefix}-nat-eip-${count.index + 1}"
  })

  depends_on = [aws_internet_gateway.main]
}

#==============================================================================
# NAT Gateways (one per public subnet for high availability)
#==============================================================================

resource "aws_nat_gateway" "main" {
  count         = 3
  allocation_id = aws_eip.nat[count.index].id
  subnet_id     = aws_subnet.public[count.index].id

  tags = merge(var.resource_tags, {
    Name = "${var.friendly_name_prefix}-nat-${count.index + 1}"
  })

  depends_on = [aws_internet_gateway.main]
}

#==============================================================================
# Route Tables
#==============================================================================

# Public route table - directs traffic to Internet Gateway
resource "aws_route_table" "public" {
  vpc_id = aws_vpc.main.id

  route {
    cidr_block      = "0.0.0.0/0"
    gateway_id      = aws_internet_gateway.main.id
  }

  tags = merge(var.resource_tags, {
    Name = "${var.friendly_name_prefix}-public-rt"
  })
}

# Public subnet route table associations
resource "aws_route_table_association" "public" {
  count          = 3
  subnet_id      = aws_subnet.public[count.index].id
  route_table_id = aws_route_table.public.id
}

# Private route tables - one per AZ for NAT Gateway redundancy
resource "aws_route_table" "private" {
  count  = 3
  vpc_id = aws_vpc.main.id

  route {
    cidr_block     = "0.0.0.0/0"
    nat_gateway_id = aws_nat_gateway.main[count.index].id
  }

  tags = merge(var.resource_tags, {
    Name = "${var.friendly_name_prefix}-private-rt-${count.index + 1}"
  })
}

# Private subnet route table associations
resource "aws_route_table_association" "private" {
  count          = 3
  subnet_id      = aws_subnet.private[count.index].id
  route_table_id = aws_route_table.private[count.index].id
}

#==============================================================================
# KMS Key for Vault Auto-Unseal
#==============================================================================

resource "aws_kms_key" "vault" {
  description             = "KMS key for Vault Enterprise auto-unseal"
  deletion_window_in_days = 10
  enable_key_rotation     = true

  tags = merge(var.resource_tags, {
    Name = "${var.friendly_name_prefix}-vault-key"
  })
}

resource "aws_kms_alias" "vault" {
  name          = "alias/${var.friendly_name_prefix}-vault"
  target_key_id = aws_kms_key.vault.key_id
}
