#==============================================================================
# Vault Enterprise HVD Module Configuration
#==============================================================================
# IMPORTANT: Prerequisites Configuration Dependency
# Before applying this configuration, you must:
#
# STEP 1: Apply prerequisites.tf (to create AWS infrastructure)
#   terraform apply -f prerequisites.tf
#   This creates: VPC, subnets, NAT Gateways, KMS key
#
# STEP 2: Create Secrets Manager secrets (manually, outside Terraform)
#   Use AWS CLI to create 4 secrets with actual content:
#     - vault-license (your Vault Enterprise license file)
#     - vault-tls-cert (TLS certificate in PEM format)
#     - vault-tls-key (TLS private key in PEM format)
#     - vault-ca-cert (CA certificate in PEM format)
#   See: AWS_SETUP_STEPS.md for AWS CLI commands
#
# STEP 3: Create terraform.tfvars for main configuration
#   Copy prerequisite outputs to terraform.tfvars
#   Add the ARNs of the 4 secrets created in STEP 2
#   See: terraform.tfvars.example for format
#
# STEP 4: Run terraform apply (main Vault module)
#   terraform apply
#   This deploys Vault Enterprise using prerequisite infrastructure
#
# See: README_DEPLOYMENT.md for complete deployment workflow

#==============================================================================
# AWS Variables
#==============================================================================

variable "aws_region" {
  description = "AWS region to deploy to"
  type        = string
  default     = "us-east-1"
}

#==============================================================================
# VPC and Network Variables
#==============================================================================

variable "vpc_id" {
  description = "VPC ID to deploy Vault into"
  type        = string
}

variable "vault_subnet_ids" {
  description = "List of subnet IDs for Vault instances (3 required, one per AZ)"
  type        = list(string)
  validation {
    condition     = length(var.vault_subnet_ids) == 3
    error_message = "Must provide exactly 3 vault subnet IDs (one per AZ)."
  }
}

variable "lb_subnet_ids" {
  description = "List of subnet IDs for load balancer (3 required, one per AZ)"
  type        = list(string)
  validation {
    condition     = length(var.lb_subnet_ids) == 3
    error_message = "Must provide exactly 3 LB subnet IDs (one per AZ)."
  }
}

variable "ingress_cidr_blocks" {
  description = "CIDR blocks allowed to access Vault API"
  type        = list(string)
  default     = ["0.0.0.0/0"]
}

variable "ingress_ssh_cidr_blocks" {
  description = "CIDR blocks allowed SSH access"
  type        = list(string)
  default     = []
}

#==============================================================================
# KMS Variables
#==============================================================================

variable "kms_key_id" {
  description = "KMS key ID for Vault auto-unseal"
  type        = string
}

#==============================================================================
# AWS Secrets Manager ARNs (Pre-created in AWS)
#==============================================================================
# These secrets must already exist in your AWS account before running terraform.
# The module's bootstrap script will fetch values from these ARNs.
# See: https://github.com/hashicorp/terraform-aws-vault-enterprise-hvd#prerequisites

variable "vault_license_secret_arn" {
  description = "ARN of AWS Secrets Manager secret containing Vault Enterprise license"
  type        = string
}

variable "vault_tls_cert_secret_arn" {
  description = "ARN of AWS Secrets Manager secret containing TLS certificate"
  type        = string
}

variable "vault_tls_key_secret_arn" {
  description = "ARN of AWS Secrets Manager secret containing TLS certificate private key"
  type        = string
}

variable "vault_ca_cert_secret_arn" {
  description = "ARN of AWS Secrets Manager secret containing CA certificate"
  type        = string
}

#==============================================================================
# Vault Configuration Variables
#==============================================================================

variable "friendly_name_prefix" {
  description = "Friendly name prefix for resources"
  type        = string
  default     = "vault"
}

variable "vault_version" {
  description = "Vault Enterprise version to deploy"
  type        = string
  default     = "1.17.0"
}

variable "node_count" {
  description = "Number of Vault nodes to deploy"
  type        = number
  default     = 3
  validation {
    condition     = var.node_count >= 3
    error_message = "Minimum 3 nodes required for HA cluster."
  }
}

variable "instance_type" {
  description = "EC2 instance type for Vault nodes"
  type        = string
  default     = "t3.large"
}

variable "vault_fqdn" {
  description = "FQDN for Vault cluster (used for TLS and cluster joining)"
  type        = string
}

variable "resource_tags" {
  description = "Tags to apply to all resources"
  type        = map(string)
  default     = {}
}
