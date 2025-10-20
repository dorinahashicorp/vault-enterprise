module "vault_ent" {
  source  = "hashicorp/vault-enterprise-hvd/aws"
  version = "0.2.0"

  # Networking
  net_vpc_id        = local.effective_vpc_id
  net_vault_subnet_ids = local.effective_vault_subnets
  net_lb_subnet_ids    = local.effective_lb_subnets

  # Resource naming
  friendly_name_prefix = var.resource_name_prefix

  # Smaller instance types for demo/learning
  vm_instance_type = "t3.medium"

  # Reduced node count: 3 nodes is minimum for HA in raft. We'll create 3
  # nodes (one per AZ) for demo purposes.
  asg_node_count = 3

  # Auto-unseal KMS key
  vault_seal_awskms_key_arn = local.effective_kms_key_arn

  # Secrets Manager ARNs - these should be populated via Terraform Cloud variable sets
  sm_vault_license_arn     = var.sm_vault_license_arn
  sm_vault_tls_cert_arn    = var.sm_vault_tls_cert_arn
  sm_vault_tls_cert_key_arn = var.sm_vault_tls_cert_key_arn
  sm_vault_tls_ca_bundle   = var.sm_vault_tls_ca_bundle

  vault_fqdn = var.vault_fqdn

  # Performance / safety defaults for small demo
  vault_disable_mlock = true

  # Optional: keep minimal amount of additional resources
  resource_tags = var.resource_tags
}

output "vault_load_balancer_dns" {
  value = module.vault_ent.vault_load_balancer_name
  description = "DNS name of the Vault load balancer"
}

output "vault_cli_config" {
  value = module.vault_ent.vault_cli_config
  description = "Suggested environment variables to configure the Vault CLI"
}
