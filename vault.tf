# Configure the Vault provider for HCP Vault Dedicated access
# Uses JWT authentication with HCP Terraform's workload identity tokens
# HCP Terraform automatically provides the token via TFC_VAULT_TOKEN environment variable
provider "vault" {
  skip_child_token = true
  address          = var.tfc_vault_dynamic_credentials.default.address
  namespace        = var.tfc_vault_dynamic_credentials.default.namespace

  auth_login_token_file {
    filename = var.tfc_vault_dynamic_credentials.default.token_filename
  }
}

# Retrieve Vault secrets from HCP Vault KV v2
data "vault_kv_secret_v2" "vault_secrets" {
  mount = var.vault_kv_mount
  name  = var.vault_kv_path_prefix
}

# Extract individual secrets for use in the module
locals {
  vault_license     = data.vault_kv_secret_v2.vault_secrets.data["license"]
  vault_server_cert = data.vault_kv_secret_v2.vault_secrets.data["server_cert"]
  vault_server_key  = data.vault_kv_secret_v2.vault_secrets.data["server_key"]
  vault_ca_cert     = data.vault_kv_secret_v2.vault_secrets.data["ca_cert"]
}
