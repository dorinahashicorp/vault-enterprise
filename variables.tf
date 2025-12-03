variable "aws_region" {
  type    = string
  default = "us-east-1"
}

variable "resource_name_prefix" {
  type    = string
  default = "demo-vault"
}

# Vault Configuration
variable "vault_addr" {
  description = "Address of the Vault server (HCP Vault Dedicated)"
  type        = string
}

variable "vault_approle_role_id" {
  description = "AppRole Role ID for Vault authentication"
  type        = string
  sensitive   = true
}

variable "vault_approle_secret_id" {
  description = "AppRole Secret ID for Vault authentication"
  type        = string
  sensitive   = true
}

variable "vault_kv_mount" {
  description = "KV mount name where secrets are stored (e.g., 'kv')"
  type        = string
  default     = "kv"
}

variable "vault_kv_path_prefix" {
  description = "Path prefix in KV mount (e.g., 'vault')"
  type        = string
  default     = "vault"
}

# Networking Configuration
variable "net_vpc_id" {
  description = "VPC id to deploy Vault into. If empty, a small demo VPC will be created by the included module."
  type        = string
  default     = ""
}

variable "net_vault_subnet_ids" {
  description = "List of subnet ids for Vault instances. If empty, the demo VPC module will supply them."
  type        = list(string)
  default     = []
}

variable "net_lb_subnet_ids" {
  description = "List of subnet ids for the load balancer. If empty, the demo VPC module will supply them."
  type        = list(string)
  default     = []
}

variable "vault_seal_awskms_key_arn" {
  description = "AWS KMS key ARN for Vault auto-unseal. If empty, a demo key will be created."
  type        = string
  default     = ""
}

variable "vault_fqdn" {
  description = "Fully qualified domain name for Vault (used for cert SANs)."
  type        = string
}

variable "resource_tags" {
  description = "Map of tags to apply to cloud resources"
  type        = map(string)
  default     = {}
}
