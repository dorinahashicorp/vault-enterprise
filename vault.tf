# Configure the Vault provider for HCP Vault Dedicated access
provider "vault" {
  address   = var.vault_addr
  namespace = "admin"

  auth_login {
    namespace = "admin"

    method = "approle"
    path   = "auth/approle/login"

    parameters = {
      role_id   = var.vault_approle_role_id
      secret_id = var.vault_approle_secret_id
    }
  }
}

# Retrieve Vault secrets from HCP Vault KV
data "vault_generic_secret" "vault_secrets" {
  path = "${var.vault_kv_mount}/${var.vault_kv_path_prefix}"
}

# Extract individual secrets for use in the module
locals {
  vault_license     = data.vault_generic_secret.vault_secrets.data["license"]
  vault_server_cert = data.vault_generic_secret.vault_secrets.data["server_cert"]
  vault_server_key  = data.vault_generic_secret.vault_secrets.data["server_key"]
  vault_ca_cert     = data.vault_generic_secret.vault_secrets.data["ca_cert"]
}
