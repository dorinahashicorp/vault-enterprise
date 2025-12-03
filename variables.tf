variable "aws_region" {
  type    = string
  default = "us-east-1"
}

# Vault Dynamic Credentials Configuration
# These values are automatically provided by HCP Terraform when TFC_VAULT_* environment variables are set
variable "tfc_vault_dynamic_credentials" {
  description = "Object containing Vault dynamic credentials configuration from HCP Terraform"
  type = object({
    default = object({
      token_filename = string
      address        = string
      namespace      = string
      ca_cert_file   = string
    })
    aliases = map(object({
      token_filename = string
      address        = string
      namespace      = string
      ca_cert_file   = string
    }))
  })
}

variable "resource_name_prefix" {
  type    = string
  default = "demo-vault"
}

# Vault Configuration
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

variable "instance_type" {
  type        = string
  description = "EC2 instance type for Vault nodes"
  default     = "t3.medium"
}

variable "node_count" {
  type        = number
  description = "Number of Vault nodes to deploy (minimum 3 for HA)"
  default     = 3

  validation {
    condition     = var.node_count >= 3
    error_message = "Minimum 3 nodes required for HA Raft cluster."
  }
}

variable "vault_version" {
  type        = string
  description = "Vault Enterprise version to deploy"
  default     = "1.17.0"
}

variable "ssh_cidr_blocks" {
  type        = list(string)
  description = "CIDR blocks allowed for SSH access (optional)"
  default     = []
}

variable "vault_api_cidr_blocks" {
  type        = list(string)
  description = "CIDR blocks allowed for Vault API access"
  default     = ["0.0.0.0/0"]
}
