variable "aws_region" {
  type    = string
  default = "us-east-1"
}

variable "resource_name_prefix" {
  type    = string
  default = "demo-vault"
}

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

variable "sm_vault_license_arn" {
  description = "ARN of the Vault license stored in AWS Secrets Manager. You must add this to the TFC variable set."
  type        = string
}

variable "sm_vault_tls_cert_arn" {
  description = "ARN of the TLS certificate secret in Secrets Manager (cert)."
  type        = string
}

variable "sm_vault_tls_cert_key_arn" {
  description = "ARN of the TLS certificate private key secret in Secrets Manager (key)."
  type        = string
}

variable "sm_vault_tls_ca_bundle" {
  description = "ARN of the CA bundle secret in Secrets Manager (CA chain)."
  type        = string
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
