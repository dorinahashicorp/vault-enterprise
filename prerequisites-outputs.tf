#==============================================================================
# Prerequisites Outputs
#==============================================================================
# These outputs from the prerequisites configuration should be copied into
# terraform.tfvars in the main Vault module configuration, or referenced
# via terraform_remote_state if using a remote state backend.

output "vpc_id" {
  description = "VPC ID - use as vpc_id in main Vault configuration"
  value       = aws_vpc.main.id
}

output "vault_subnet_ids" {
  description = "Private subnet IDs for Vault instances - use as vault_subnet_ids in main configuration"
  value       = aws_subnet.private[*].id
}

output "lb_subnet_ids" {
  description = "Public subnet IDs for load balancer - use as lb_subnet_ids in main configuration"
  value       = aws_subnet.public[*].id
}

output "kms_key_arn" {
  description = "ARN of KMS key for auto-unseal - use as kms_key_id in main configuration"
  value       = aws_kms_key.vault.arn
}

output "prerequisites_summary" {
  description = "Summary of created prerequisites"
  value = {
    vpc_id           = aws_vpc.main.id
    vault_subnet_ids = aws_subnet.private[*].id
    lb_subnet_ids    = aws_subnet.public[*].id
    kms_key_arn      = aws_kms_key.vault.arn
    next_step        = "1. Create 4 Secrets Manager secrets with your certificate and license content. 2. Copy the above values and secret ARNs to terraform.tfvars. 3. Run terraform apply."
  }
}
