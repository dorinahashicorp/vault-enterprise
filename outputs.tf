output "vault_lb_dns_name" {
  description = "Vault load balancer DNS name"
  value       = module.vault_ent.vault_load_balancer_name
}

output "vault_cli_env" {
  description = "Environment variables to set for vault CLI (example)"
  value       = module.vault_ent.vault_cli_config
}
