#==============================================================================
# Prerequisites Variables
#==============================================================================
# These variables are used by prerequisites.tf to create foundational AWS
# resources (VPC, KMS, Secrets Manager). The outputs from this configuration
# feed into the main Vault module configuration.

variable "aws_region" {
  description = "AWS region to deploy resources"
  type        = string
  default     = "us-east-1"
}

variable "vpc_cidr" {
  description = "CIDR block for VPC (will be divided into 6 subnets: 3 public, 3 private)"
  type        = string
  default     = "10.0.0.0/16"

  validation {
    condition     = can(cidrhost(var.vpc_cidr, 0))
    error_message = "VPC CIDR must be a valid IPv4 CIDR block."
  }
}

variable "friendly_name_prefix" {
  description = "Prefix for all resource names (e.g., vault, production-vault)"
  type        = string
  default     = "vault"

  validation {
    condition     = length(var.friendly_name_prefix) <= 20
    error_message = "Friendly name prefix must be 20 characters or less."
  }
}

variable "resource_tags" {
  description = "Tags to apply to all resources"
  type        = map(string)
  default     = {}
}
