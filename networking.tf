locals {
  demo_suffix = "-demo"
}

# Optional demo VPC: created only when net_vpc_id is not provided.
module "demo_vpc" {
  source  = "terraform-aws-modules/vpc/aws"
  version = "~> 3.0"

  count = var.net_vpc_id == "" ? 1 : 0

  name = "${var.resource_name_prefix}${local.demo_suffix}"
  cidr = "10.50.0.0/16"

  azs             = slice(data.aws_availability_zones.available.names, 0, 3)
  public_subnets  = ["10.50.1.0/24", "10.50.2.0/24", "10.50.3.0/24"]
  private_subnets = ["10.50.11.0/24", "10.50.12.0/24", "10.50.13.0/24"]

  enable_nat_gateway = false
  enable_dns_hostnames = true
  enable_dns_support = true
}

data "aws_availability_zones" "available" {}

# Determine effective VPC and subnet lists
locals {
  effective_vpc_id = var.net_vpc_id != "" ? var.net_vpc_id : module.demo_vpc[0].vpc_id
  effective_vault_subnets = length(var.net_vault_subnet_ids) > 0 ? var.net_vault_subnet_ids : module.demo_vpc[0].private_subnets
  effective_lb_subnets    = length(var.net_lb_subnet_ids) > 0 ? var.net_lb_subnet_ids : module.demo_vpc[0].public_subnets
}

resource "aws_kms_key" "vault_auto_unseal" {
  count = var.vault_seal_awskms_key_arn == "" ? 1 : 0

  description = "Demo KMS key for Vault auto-unseal (created by terraform)"
  deletion_window_in_days = 7
}

resource "aws_kms_alias" "vault_auto_unseal_alias" {
  count = var.vault_seal_awskms_key_arn == "" ? 1 : 0

  name          = "alias/${var.resource_name_prefix}-vault-unseal"
  target_key_id = aws_kms_key.vault_auto_unseal[0].key_id
}

locals {
  effective_kms_key_arn = var.vault_seal_awskms_key_arn != "" ? var.vault_seal_awskms_key_arn : aws_kms_key.vault_auto_unseal[0].arn
}
