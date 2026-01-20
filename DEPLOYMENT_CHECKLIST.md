# Vault Enterprise Deployment Checklist

Use this checklist to ensure you complete all required steps before and during deployment.

## Pre-Deployment Checklist

### 1. Prepare Your Files

- [ ] Have Vault Enterprise license file (`.hclic`) ready
- [ ] Have TLS certificate (PEM format) ready
- [ ] Have TLS private key (PEM format) ready
- [ ] Have CA certificate bundle (PEM format) ready

### 2. HCP Terraform Workspace Configuration

- [x] Workspace `vault-enterprise` created
- [x] AWS credentials configured (environment variables)
- [x] Variable `vault_fqdn` set to `vault.infragoose.com`

#### Add Sensitive Variables

- [ ] Add `vault_license` variable (mark as sensitive)
  - Copy entire content of `.hclic` file
  - Paste into variable value
  - Check "Sensitive" checkbox

- [ ] Add `vault_tls_cert` variable (mark as sensitive)
  - Copy entire TLS certificate (PEM format)
  - Include full certificate chain
  - Check "Sensitive" checkbox

- [ ] Add `vault_tls_key` variable (mark as sensitive)
  - Copy entire private key (PEM format)
  - Check "Sensitive" checkbox

- [ ] Add `vault_ca_bundle` variable (mark as sensitive)
  - Copy entire CA bundle (PEM format)
  - Check "Sensitive" checkbox

### 3. Optional Configuration (has defaults)

- [ ] Review and adjust `vpc_cidr` if needed (default: 10.0.0.0/16)
- [ ] Review and adjust `resource_name_prefix` (default: vault)
- [ ] Review and adjust `vault_version` (default: 1.18.2+ent)
- [ ] Review and adjust `asg_node_count` (default: 6)
- [ ] Review and adjust `vm_instance_type` (default: m7i.large)
- [ ] Review and adjust `load_balancing_scheme` (default: INTERNAL)

## Deployment Checklist

### 1. Initialize Terraform

- [ ] Run `terraform init`
- [ ] Verify connection to HCP Terraform workspace
- [ ] Confirm providers and modules downloaded successfully

### 2. Plan Deployment

- [ ] Run `terraform plan`
- [ ] Review planned resources (~40-50 resources)
- [ ] Verify VPC CIDR doesn't conflict with existing networks
- [ ] Confirm subnet allocations are correct
- [ ] Review security group rules
- [ ] Verify KMS key settings
- [ ] Confirm AWS Secrets Manager secrets will be created

### 3. Apply Configuration

- [ ] Run `terraform apply`
- [ ] Type `yes` to confirm
- [ ] Wait for deployment to complete (~10-15 minutes)
- [ ] Verify no errors occurred

### 4. Capture Outputs

- [ ] Run `terraform output` to view all outputs
- [ ] Save `vault_lb_dns_name` for DNS configuration
- [ ] Save `vault_lb_zone_id` (if using Route 53)
- [ ] Save `kms_key_arn` for reference
- [ ] Save `vpc_id` and `subnet_ids` for reference
- [ ] Note the Secret ARNs created in AWS Secrets Manager

## Post-Deployment Checklist

### 1. DNS Configuration

- [ ] Create DNS record for `vault.infragoose.com`
- [ ] Point to `vault_lb_dns_name` output
- [ ] Wait for DNS propagation
- [ ] Verify with `dig vault.infragoose.com`

### 2. Initialize Vault Cluster

- [ ] Set `VAULT_ADDR="https://vault.infragoose.com:8200"`
- [ ] Run `vault operator init`
- [ ] **CRITICAL**: Save all 5 unseal keys securely
- [ ] **CRITICAL**: Save root token securely
- [ ] Store keys in secure location (password manager, vault, etc.)
- [ ] Verify auto-unseal with `vault status`

### 3. Basic Vault Configuration

- [ ] Enable audit logging
  ```bash
  vault audit enable file file_path=/opt/vault/audit/audit.log
  ```

- [ ] Create admin policy
- [ ] Enable authentication method (userpass, OIDC, etc.)
- [ ] Create admin users
- [ ] Test access to Vault UI

### 4. Verification

- [ ] Verify all 6 nodes are running and healthy
  ```bash
  vault operator raft list-peers
  ```

- [ ] Check cluster status
  ```bash
  vault status
  ```

- [ ] Verify load balancer health checks are passing
- [ ] Test API access from different locations
- [ ] Verify auto-unseal is working
- [ ] Test failover (optional but recommended)

## Security Hardening Checklist

- [ ] Rotate root token or revoke it (use other auth methods)
- [ ] Enable MFA for admin accounts
- [ ] Configure network ACLs if needed
- [ ] Review security group rules
- [ ] Enable AWS CloudTrail for API auditing
- [ ] Configure AWS Config for compliance
- [ ] Set up automated security scanning
- [ ] Document disaster recovery procedures

## Monitoring Setup Checklist

- [ ] Configure CloudWatch alarms for:
  - [ ] EC2 instance health
  - [ ] ALB healthy target count
  - [ ] ALB 4xx/5xx errors
  - [ ] EBS volume metrics
  - [ ] NAT Gateway metrics

- [ ] Set up log aggregation (optional)
- [ ] Configure Vault telemetry (optional)
- [ ] Set up alerting (PagerDuty, Slack, etc.)

## Backup and DR Checklist

- [ ] Configure automated Raft snapshots (optional)
  - [ ] Create S3 bucket
  - [ ] Configure snapshot schedule
  - [ ] Test restore procedure

- [ ] Document recovery procedures
- [ ] Test disaster recovery plan
- [ ] Set up cross-region replication (optional)

## Documentation Checklist

- [ ] Document deployment architecture
- [ ] Document access procedures
- [ ] Document escalation procedures
- [ ] Create runbooks for common operations
- [ ] Document disaster recovery procedures
- [ ] Share knowledge with team

## Compliance Checklist (if applicable)

- [ ] Review compliance requirements
- [ ] Enable required audit logs
- [ ] Configure data encryption settings
- [ ] Document security controls
- [ ] Prepare for compliance audit

---

## Quick Reference

**Vault URL**: https://vault.infragoose.com:8200
**Vault UI**: https://vault.infragoose.com:8200/ui
**Region**: us-east-1
**Cluster Size**: 6 nodes across 3 AZs
**Auto-Unseal**: AWS KMS
**Secrets**: Managed via HCP Terraform workspace variables → AWS Secrets Manager

**Required HCP Terraform Variables (Sensitive)**:
- `vault_fqdn` (already set)
- `vault_license`
- `vault_tls_cert`
- `vault_tls_key`
- `vault_ca_bundle`

**Support Resources**:
- [Vault Documentation](https://developer.hashicorp.com/vault)
- [HVD Module](https://registry.terraform.io/modules/hashicorp/vault-enterprise-hvd/aws)
- [HashiCorp Discuss](https://discuss.hashicorp.com/c/vault)

---

**Note**: Check off items as you complete them to track your progress through the deployment.
