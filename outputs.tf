output "vault_lb_dns_name" {
  description = "Vault load balancer DNS name"
  value       = aws_lb.vault.dns_name
}

output "vault_root_token" {
  description = "Vault root token (sensitive - written to instance /opt/vault/root_token.txt after initialization)"
  value       = "Root token is stored in /opt/vault/root_token.txt on the Vault instances after initialization completes (5-10 minutes)"
  sensitive   = false
}

output "vault_cli_env" {
  description = "Environment variables to set for vault CLI"
  value       = "export VAULT_ADDR=https://${aws_lb.vault.dns_name}:8200\nexport VAULT_NAMESPACE=admin"
  sensitive   = false
}

output "vault_root_token_secret_name" {
  description = "AWS Secrets Manager secret name containing the root token"
  value       = "${var.resource_name_prefix}-vault-root-token"
}

output "vault_retrieve_root_token" {
  description = "Command to retrieve the root token from AWS Secrets Manager"
  value       = "aws secretsmanager get-secret-value --secret-id ${var.resource_name_prefix}-vault-root-token --region ${var.aws_region} --query SecretString --output text | jq -r '.root_token'"
  sensitive   = false
}

output "vault_quick_start_guide" {
  description = "Quick start guide for accessing your Vault cluster"
  value       = <<-EOT

╔════════════════════════════════════════════════════════════════╗
║         VAULT CLUSTER DEPLOYED WITH KMS AUTO-UNSEAL            ║
╚════════════════════════════════════════════════════════════════╝

This cluster uses AWS KMS for automatic unsealing. No manual unseal
keys are required.

1. Retrieve your root token:
   ROOT_TOKEN=$(aws secretsmanager get-secret-value \
     --secret-id ${var.resource_name_prefix}-vault-root-token \
     --region ${var.aws_region} \
     --query SecretString --output text | jq -r '.root_token')

2. Set environment variables:
   export VAULT_ADDR=https://${aws_lb.vault.dns_name}:8200
   export VAULT_TOKEN=$ROOT_TOKEN
   export VAULT_SKIP_VERIFY=true  # For self-signed certs

3. Verify cluster is operational:
   vault status

4. Check cluster members (Raft):
   vault operator raft list-peers

5. Unseal status (should show sealed: false, auto-unsealed by KMS):
   vault status | grep sealed

⚠️  IMPORTANT SECURITY NOTES:
   - Store the root token securely (consider rotating it via auth methods)
   - Set up authentication methods (e.g., AppRole, JWT, OIDC) for applications
   - Do NOT use root token for normal operations; create limited-scope tokens
   - Use 'vault write auth/...' to configure auth methods for your use case

Next steps:
   1. Set up AppRole auth for application access
   2. Create policies for different teams/applications
   3. Enable audit logging
   4. Configure backup strategy for Raft storage

EOT
  sensitive   = false
}
