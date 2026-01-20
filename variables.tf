################################################################################
# General Configuration
################################################################################

variable "aws_region" {
  description = "AWS region where Vault will be deployed"
  type        = string
  default     = "us-east-1"
}

variable "environment" {
  description = "Environment name (e.g., dev, staging, prod)"
  type        = string
  default     = "prod"
}

variable "resource_name_prefix" {
  description = "Prefix for resource names (e.g., infragoose-prod)"
  type        = string
  default     = "vault"
}

################################################################################
# Network Configuration - Auto-created
################################################################################

variable "vpc_cidr" {
  description = "CIDR block for the VPC"
  type        = string
  default     = "10.0.0.0/16"
}

variable "kms_deletion_window" {
  description = "KMS key deletion window in days"
  type        = number
  default     = 10
}

################################################################################
# Vault FQDN - REQUIRED
################################################################################

variable "vault_fqdn" {
  description = "Fully qualified domain name for Vault (e.g., vault.infragoose.com)"
  type        = string
}

################################################################################
# Vault License and TLS Certificates - REQUIRED
# Add these as sensitive variables in HCP Terraform workspace
################################################################################

variable "vault_license" {
  description = "Vault Enterprise license content (entire .hclic file content)"
  type        = string
  sensitive   = true
}

variable "vault_tls_cert" {
  description = "TLS certificate in PEM format (include full chain)"
  type        = string
  sensitive   = true
}

variable "vault_tls_key" {
  description = "TLS certificate private key in PEM format"
  type        = string
  sensitive   = true
}

variable "vault_ca_bundle" {
  description = "CA certificate bundle in PEM format"
  type        = string
  sensitive   = true
}


################################################################################
# Vault Configuration - Optional
################################################################################

variable "vault_version" {
  description = "Version of Vault Enterprise to deploy"
  type        = string
  default     = "1.18.2+ent"
}

variable "asg_node_count" {
  description = "Number of Vault nodes in the Auto Scaling Group (recommended: 5-6 for HA)"
  type        = number
  default     = 6
}

variable "vm_instance_type" {
  description = "EC2 instance type for Vault nodes"
  type        = string
  default     = "m7i.large"
}

variable "vault_default_lease_ttl_duration" {
  description = "Default lease TTL for Vault secrets"
  type        = string
  default     = "1h"
}

variable "vault_max_lease_ttl_duration" {
  description = "Maximum lease TTL for Vault secrets"
  type        = string
  default     = "768h"
}

variable "vault_port_api" {
  description = "Port for Vault API"
  type        = string
  default     = "8200"
}

variable "vault_port_cluster" {
  description = "Port for Vault cluster communication"
  type        = string
  default     = "8201"
}

variable "load_balancing_scheme" {
  description = "Load balancer scheme: INTERNAL (private) or EXTERNAL (public)"
  type        = string
  default     = "INTERNAL"
  validation {
    condition     = contains(["INTERNAL", "EXTERNAL", "NONE"], var.load_balancing_scheme)
    error_message = "Load balancing scheme must be INTERNAL, EXTERNAL, or NONE."
  }
}

variable "vault_raft_performance_multiplier" {
  description = "Raft performance multiplier (1-10). Lower values increase sensitivity to leader heartbeat timeouts."
  type        = number
  default     = 5
}

################################################################################
# Storage Configuration - Optional
################################################################################

variable "vm_boot_disk_configuration" {
  description = "Boot disk configuration for Vault EC2 instances"
  type = object({
    volume_type = string
    volume_size = number
    iops        = optional(number)
    throughput  = optional(number)
    encrypted   = bool
  })
  default = {
    volume_type = "gp3"
    volume_size = 30
    encrypted   = true
  }
}

variable "vm_vault_data_disk_configuration" {
  description = "Data disk configuration for Vault storage (Raft)"
  type = object({
    volume_type = string
    volume_size = number
    iops        = optional(number)
    throughput  = optional(number)
    encrypted   = bool
  })
  default = {
    volume_type = "gp3"
    volume_size = 100
    iops        = 3000
    throughput  = 125
    encrypted   = true
  }
}

variable "vm_vault_audit_disk_configuration" {
  description = "Audit disk configuration for Vault audit logs"
  type = object({
    volume_type = string
    volume_size = number
    iops        = optional(number)
    throughput  = optional(number)
    encrypted   = bool
  })
  default = {
    volume_type = "gp3"
    volume_size = 50
    encrypted   = true
  }
}

variable "vault_snapshots_bucket_arn" {
  description = "ARN of S3 bucket for automated Raft snapshots (optional)"
  type        = string
  default     = null
}

################################################################################
# Additional Tags - Optional
################################################################################

variable "common_tags" {
  description = "Additional tags to apply to all resources"
  type        = map(string)
  default     = {}
}
