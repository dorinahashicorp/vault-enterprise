################################################################################
# AWS Secrets Manager - Managed by Terraform
#
# This file creates AWS Secrets Manager secrets from Terraform variables.
# You can add your license and TLS certs directly to HCP Terraform workspace
# instead of manually uploading to AWS Secrets Manager.
################################################################################

################################################################################
# Vault Enterprise License
################################################################################

resource "aws_secretsmanager_secret" "vault_license" {
  name_prefix             = "${var.resource_name_prefix}-vault-license-"
  description             = "Vault Enterprise license"
  recovery_window_in_days = 0 # Allows immediate deletion for testing

  tags = {
    Name = "${var.resource_name_prefix}-vault-license"
  }
}

resource "aws_secretsmanager_secret_version" "vault_license" {
  secret_id     = aws_secretsmanager_secret.vault_license.id
  secret_string = var.vault_license
}

################################################################################
# TLS Certificate
################################################################################

resource "aws_secretsmanager_secret" "vault_tls_cert" {
  name_prefix             = "${var.resource_name_prefix}-vault-tls-cert-"
  description             = "Vault TLS certificate (PEM format)"
  recovery_window_in_days = 0

  tags = {
    Name = "${var.resource_name_prefix}-vault-tls-cert"
  }
}

resource "aws_secretsmanager_secret_version" "vault_tls_cert" {
  secret_id     = aws_secretsmanager_secret.vault_tls_cert.id
  secret_string = var.vault_tls_cert
}

################################################################################
# TLS Private Key
################################################################################

resource "aws_secretsmanager_secret" "vault_tls_key" {
  name_prefix             = "${var.resource_name_prefix}-vault-tls-key-"
  description             = "Vault TLS certificate private key (PEM format)"
  recovery_window_in_days = 0

  tags = {
    Name = "${var.resource_name_prefix}-vault-tls-key"
  }
}

resource "aws_secretsmanager_secret_version" "vault_tls_key" {
  secret_id     = aws_secretsmanager_secret.vault_tls_key.id
  secret_string = var.vault_tls_key
}

################################################################################
# CA Bundle
################################################################################

resource "aws_secretsmanager_secret" "vault_ca_bundle" {
  name_prefix             = "${var.resource_name_prefix}-vault-ca-bundle-"
  description             = "CA certificate bundle (PEM format)"
  recovery_window_in_days = 0

  tags = {
    Name = "${var.resource_name_prefix}-vault-ca-bundle"
  }
}

resource "aws_secretsmanager_secret_version" "vault_ca_bundle" {
  secret_id     = aws_secretsmanager_secret.vault_ca_bundle.id
  secret_string = var.vault_ca_bundle
}

################################################################################
# Outputs for use in main.tf
################################################################################

output "vault_license_arn" {
  description = "ARN of Vault license secret"
  value       = aws_secretsmanager_secret.vault_license.arn
}

output "vault_tls_cert_arn" {
  description = "ARN of Vault TLS certificate secret"
  value       = aws_secretsmanager_secret.vault_tls_cert.arn
}

output "vault_tls_key_arn" {
  description = "ARN of Vault TLS private key secret"
  value       = aws_secretsmanager_secret.vault_tls_key.arn
}

output "vault_ca_bundle_arn" {
  description = "ARN of Vault CA bundle secret"
  value       = aws_secretsmanager_secret.vault_ca_bundle.arn
}
