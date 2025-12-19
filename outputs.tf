#==============================================================================
# Outputs
#==============================================================================

output "vault_load_balancer_dns" {
  description = "DNS name of the load balancer for accessing Vault"
  value       = module.vault.vault_load_balancer_name
}

output "vault_cli_env" {
  description = "Environment variables for Vault CLI configuration"
  value       = module.vault.vault_cli_config
}

output "vault_address" {
  description = "Vault cluster address"
  value       = "https://${module.vault.vault_load_balancer_name}:8200"
}

output "vault_nodes" {
  description = "Details of deployed Vault nodes"
  value = {
    count  = var.node_count
    subnet_ids = var.vault_subnet_ids
    instance_type = var.instance_type
  }
}

output "security_group_id" {
  description = "Security group ID for Vault nodes"
  value       = try(module.vault.security_group_id, "N/A")
}
