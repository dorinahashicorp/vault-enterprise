output "vault_lb_dns_name" {
  description = "Vault load balancer DNS name"
  value       = aws_lb.vault.dns_name
}

output "vault_cli_env" {
  description = "Environment variables to set for vault CLI"
  value       = "export VAULT_ADDR=https://${aws_lb.vault.dns_name}:8200\nexport VAULT_NAMESPACE=admin"
  sensitive   = true
}
