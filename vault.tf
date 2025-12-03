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
