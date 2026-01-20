################################################################################
# Infrastructure Outputs
################################################################################

output "vpc_id" {
  description = "VPC ID"
  value       = aws_vpc.vault.id
}

output "private_subnet_ids" {
  description = "Private subnet IDs"
  value       = aws_subnet.private[*].id
}

output "public_subnet_ids" {
  description = "Public subnet IDs"
  value       = aws_subnet.public[*].id
}

output "kms_key_arn" {
  description = "KMS key ARN for Vault auto-unseal"
  value       = aws_kms_key.vault_unseal.arn
}

output "kms_key_alias" {
  description = "KMS key alias"
  value       = aws_kms_alias.vault_unseal.name
}

output "availability_zones" {
  description = "Availability zones used for deployment"
  value       = slice(data.aws_availability_zones.available.names, 0, 3)
}

################################################################################
# Vault Cluster Outputs
################################################################################

output "vault_fqdn" {
  description = "Fully qualified domain name for the Vault cluster"
  value       = var.vault_fqdn
}

output "vault_lb_dns_name" {
  description = "DNS name of the Vault load balancer"
  value       = module.vault_enterprise_hvd.vault_lb_dns_name
}

output "vault_lb_zone_id" {
  description = "Route53 zone ID of the Vault load balancer"
  value       = module.vault_enterprise_hvd.vault_lb_zone_id
}

output "vault_lb_arn" {
  description = "ARN of the Vault load balancer"
  value       = module.vault_enterprise_hvd.vault_lb_arn
}

output "vault_api_url" {
  description = "Full URL for Vault API access"
  value       = "https://${var.vault_fqdn}:${var.vault_port_api}"
}

################################################################################
# Auto Scaling Group Outputs
################################################################################

output "vault_asg_name" {
  description = "Name of the Vault Auto Scaling Group"
  value       = module.vault_enterprise_hvd.vault_asg_name
}

output "vault_asg_arn" {
  description = "ARN of the Vault Auto Scaling Group"
  value       = module.vault_enterprise_hvd.vault_asg_arn
}

################################################################################
# Security Group Outputs
################################################################################

output "vault_sg_id" {
  description = "Security group ID for Vault instances"
  value       = module.vault_enterprise_hvd.vault_sg_id
}

output "vault_lb_sg_id" {
  description = "Security group ID for Vault load balancer"
  value       = module.vault_enterprise_hvd.vault_lb_sg_id
}

################################################################################
# IAM Outputs
################################################################################

output "vault_instance_role_arn" {
  description = "ARN of the IAM role attached to Vault instances"
  value       = module.vault_enterprise_hvd.vault_instance_role_arn
}

output "vault_instance_profile_arn" {
  description = "ARN of the IAM instance profile for Vault instances"
  value       = module.vault_enterprise_hvd.vault_instance_profile_arn
}

################################################################################
# Deployment Information
################################################################################

output "deployment_info" {
  description = "Important information about the Vault deployment"
  value = {
    cluster_size  = var.asg_node_count
    instance_type = var.vm_instance_type
    vault_version = var.vault_version
    load_balancer = var.load_balancing_scheme
    auto_unseal   = "Enabled (AWS KMS)"
    region        = var.aws_region
    environment   = var.environment
    vpc_cidr      = var.vpc_cidr
  }
}

################################################################################
# Next Steps
################################################################################

output "next_steps" {
  description = "Post-deployment instructions"
  value       = <<-EOT

    Vault Enterprise cluster has been deployed successfully!

    Next Steps:
    1. Create a DNS record for ${var.vault_fqdn} pointing to the load balancer:
       - DNS Name: ${var.vault_fqdn}
       - Target: ${module.vault_enterprise_hvd.vault_lb_dns_name}
       - Type: CNAME (or ALIAS if using Route53)

    2. Initialize the Vault cluster:
       export VAULT_ADDR="https://${var.vault_fqdn}:${var.vault_port_api}"
       vault operator init

       IMPORTANT: Save the unseal keys and root token securely!

    3. The cluster will auto-unseal using AWS KMS after initialization.

    4. Check cluster status:
       vault status

    5. Access the Vault UI:
       https://${var.vault_fqdn}:${var.vault_port_api}/ui

    For more information, see: https://developer.hashicorp.com/vault/docs
  EOT
}
