################################################################################
# HashiCorp Validated Design (HVD) - Vault Enterprise on AWS
################################################################################

module "vault_enterprise_hvd" {
  source  = "hashicorp/vault-enterprise-hvd/aws"
  version = "0.2.0"

  # Dependency: Wait for infrastructure and secrets to be ready
  depends_on = [
    aws_vpc.vault,
    aws_subnet.private,
    aws_subnet.public,
    aws_nat_gateway.vault,
    aws_kms_key.vault_unseal,
    aws_vpc_endpoint.secretsmanager,
    aws_vpc_endpoint.kms,
    aws_vpc_endpoint.ec2,
    aws_secretsmanager_secret_version.vault_license,
    aws_secretsmanager_secret_version.vault_tls_cert,
    aws_secretsmanager_secret_version.vault_tls_key,
    aws_secretsmanager_secret_version.vault_ca_bundle
  ]

  #-----------------------------------------------------------------------------
  # Required Variables - Using auto-created infrastructure
  #-----------------------------------------------------------------------------

  # Network Configuration (from infrastructure.tf)
  net_vpc_id            = aws_vpc.vault.id
  net_vault_subnet_ids  = aws_subnet.private[*].id
  net_lb_subnet_ids     = var.load_balancing_scheme == "INTERNAL" ? aws_subnet.private[*].id : aws_subnet.public[*].id

  # Vault FQDN
  vault_fqdn = var.vault_fqdn

  # AWS Secrets Manager ARNs for License and TLS (from secrets.tf)
  sm_vault_license_arn       = aws_secretsmanager_secret.vault_license.arn
  sm_vault_tls_cert_arn      = aws_secretsmanager_secret.vault_tls_cert.arn
  sm_vault_tls_cert_key_arn  = aws_secretsmanager_secret.vault_tls_key.arn
  sm_vault_tls_ca_bundle     = aws_secretsmanager_secret.vault_ca_bundle.arn

  # KMS Auto-Unseal (from infrastructure.tf)
  vault_seal_awskms_key_arn = aws_kms_key.vault_unseal.arn

  #-----------------------------------------------------------------------------
  # Optional Configuration
  #-----------------------------------------------------------------------------

  # Vault Version and Cluster Size
  vault_version  = var.vault_version
  asg_node_count = var.asg_node_count

  # Instance Configuration
  vm_instance_type = var.vm_instance_type

  # Vault TTL Configuration
  vault_default_lease_ttl_duration = var.vault_default_lease_ttl_duration
  vault_max_lease_ttl_duration     = var.vault_max_lease_ttl_duration

  # Vault Ports
  vault_port_api     = var.vault_port_api
  vault_port_cluster = var.vault_port_cluster

  # Load Balancing
  load_balancing_scheme = var.load_balancing_scheme

  # Raft Configuration
  vault_raft_performance_multiplier = var.vault_raft_performance_multiplier

  # Disk Configurations
  vm_boot_disk_configuration        = var.vm_boot_disk_configuration
  vm_vault_data_disk_configuration  = var.vm_vault_data_disk_configuration
  vm_vault_audit_disk_configuration = var.vm_vault_audit_disk_configuration

  # Optional Snapshots Bucket
  vault_snapshots_bucket_arn = var.vault_snapshots_bucket_arn

  # Additional Tags
  common_tags = merge(
    var.common_tags,
    {
      Environment = var.environment
      ManagedBy   = "terraform"
      Module      = "vault-enterprise-hvd"
    }
  )
}
