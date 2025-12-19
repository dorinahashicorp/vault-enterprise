#==============================================================================
# Vault Enterprise Module from HashiCorp
#==============================================================================
# Official Validated Deployment module from HashiCorp
# Source: https://github.com/hashicorp/terraform-aws-vault-enterprise-hvd
#
# DEPENDENCY: This module requires AWS prerequisites to be in place first.
# These prerequisites are created by prerequisites.tf:
#   - VPC: aws_vpc.main
#   - Subnets: aws_subnet.private[*], aws_subnet.public[*]
#   - KMS: aws_kms_key.vault
#   - Secrets Manager: aws_secretsmanager_secret.vault_*
#   - NAT Gateways: aws_nat_gateway.main[*]
#
# The values for the module inputs (vpc_id, subnet_ids, kms_key_arn, secret ARNs)
# come from the prerequisites configuration outputs.
#
# This module is used exactly as documented with no modifications.
# All prerequisites must be in place in AWS before running terraform apply.

module "vault" {
  source  = "hashicorp/terraform-aws-vault-enterprise-hvd/aws"
  version = "~> 0.2"

  # Common Configuration
  friendly_name_prefix = var.friendly_name_prefix
  vault_fqdn           = var.vault_fqdn
  resource_tags        = var.resource_tags

  # Networking - Required
  # These come from prerequisites.tf outputs
  net_vpc_id           = var.vpc_id
  net_vault_subnet_ids = var.vault_subnet_ids
  net_lb_subnet_ids    = var.lb_subnet_ids

  # Network Security
  net_ingress_vault_cidr_blocks = var.ingress_cidr_blocks
  net_ingress_ssh_cidr_blocks   = var.ingress_ssh_cidr_blocks
  load_balancing_scheme         = "INTERNAL"

  # AWS Secrets Manager - Created by prerequisites.tf
  # Dependency: Requires aws_secretsmanager_secret.vault_* to exist
  # These secrets are created as placeholders and must be populated manually
  sm_vault_license_arn      = var.vault_license_secret_arn
  sm_vault_tls_cert_arn     = var.vault_tls_cert_secret_arn
  sm_vault_tls_cert_key_arn = var.vault_tls_key_secret_arn
  sm_vault_tls_ca_bundle    = var.vault_ca_cert_secret_arn

  # KMS Configuration - Created by prerequisites.tf
  # Dependency: Requires aws_kms_key.vault to exist
  vault_seal_awskms_key_arn = var.kms_key_id

  # Vault Configuration
  vault_version        = var.vault_version
  asg_node_count       = var.node_count
  vm_instance_type     = var.instance_type

  # Vault Features
  vault_disable_mlock = false
  vault_enable_ui     = true
}
