# Vault Enterprise Deployment Checklist

Use this checklist to ensure you complete all required steps for a successful Vault Enterprise deployment on AWS.

## Pre-Deployment Checklist

### 1. Gather Required Files and Information

- [ ] Vault Enterprise license file (`.hclic`)
- [ ] TLS certificate (PEM format, including full certificate chain)
- [ ] TLS private key (PEM format)
- [ ] CA certificate bundle (PEM format)
- [ ] AWS account with appropriate permissions
- [ ] DNS domain name where you can create records (e.g., `vault.example.com`)

### 2. Setup HCP Terraform Workspace

- [ ] Create HCP Terraform account at https://app.terraform.io
- [ ] Create a new workspace or identify existing workspace to use
- [ ] Note your organization name: `________________`
- [ ] Note your workspace name: `________________`
- [ ] Choose workflow type (VCS-backed recommended, or CLI)

### 3. Configure Terraform Backend

- [ ] Edit `terraform.tf` in this repository
- [ ] Update `organization` value to match your organization
- [ ] Update `workspace name` value to match your workspace

### 4. Configure AWS Credentials

Add these as **environment variables** in your HCP Terraform workspace:

- [ ] Add `AWS_ACCESS_KEY_ID` (mark as sensitive)
- [ ] Add `AWS_SECRET_ACCESS_KEY` (mark as sensitive)
- [ ] Add `AWS_SESSION_TOKEN` (if using temporary credentials, mark as sensitive)

### 5. Configure Required Terraform Variables

Add these as **Terraform variables** in your HCP Terraform workspace (all marked as sensitive):

- [ ] `vault_fqdn` (string, sensitive)
  - Your Vault domain name (e.g., `vault.example.com`)

- [ ] `vault_license` (string, sensitive)
  - Copy entire content of `.hclic` file
  - Paste into variable value
  - **Check "Sensitive" checkbox**

- [ ] `vault_tls_cert` (string, sensitive)
  - Copy entire TLS certificate (PEM format)
  - Must include full certificate chain
  - **Check "Sensitive" checkbox**

- [ ] `vault_tls_key` (string, sensitive)
  - Copy entire private key (PEM format)
  - **Check "Sensitive" checkbox**

- [ ] `vault_ca_bundle` (string, sensitive)
  - Copy entire CA bundle (PEM format)
  - **Check "Sensitive" checkbox**

### 6. Review Optional Configuration (Has Sensible Defaults)

These are optional - only set if you need to override defaults:

- [ ] Review `aws_region` (default: `us-east-1`)
- [ ] Review `environment` (default: `prod`)
- [ ] Review `resource_name_prefix` (default: `vault`)
- [ ] Review `vpc_cidr` (default: `10.0.0.0/16`)
- [ ] Review `vault_version` (default: `1.18.2+ent`)
- [ ] Review `asg_node_count` (default: `6`)
- [ ] Review `vm_instance_type` (default: `m7i.large`)
- [ ] Review `load_balancing_scheme` (default: `INTERNAL`)
- [ ] Review `kms_deletion_window` (default: `10` days)

See `terraform.tfvars.example` for all available options.

## Deployment Checklist

### 1. Initialize Terraform

- [ ] Clone or download this repository locally
- [ ] Open terminal in repository directory
- [ ] Run `terraform login` (if not already authenticated)
- [ ] Run `terraform init`
- [ ] Verify connection to HCP Terraform workspace succeeds
- [ ] Confirm providers and modules downloaded successfully

### 2. Plan Deployment

- [ ] Run `terraform plan`
- [ ] Review output - should show ~40-50 resources to be created
- [ ] Verify VPC CIDR doesn't conflict with existing networks
- [ ] Confirm subnet allocations look correct
- [ ] Review security group rules
- [ ] Verify KMS key configuration
- [ ] Confirm AWS Secrets Manager secrets will be created
- [ ] Review load balancer configuration (INTERNAL vs EXTERNAL)

### 3. Apply Configuration

- [ ] Run `terraform apply`
- [ ] Review the plan once more
- [ ] Type `yes` to confirm deployment
- [ ] Wait for deployment to complete (~10-15 minutes)
- [ ] Verify no errors occurred during apply

### 4. Capture Terraform Outputs

- [ ] Run `terraform output` to view all outputs
- [ ] Record output values for reference:
  - [ ] `vault_load_balancer_name`: `________________`
  - [ ] `vault_fqdn`: `________________`
  - [ ] `vault_api_url`: `________________`
  - [ ] `kms_key_arn`: `________________`
  - [ ] `vpc_id`: `________________`
  - [ ] `private_subnet_ids`: `________________`
  - [ ] `availability_zones`: `________________`

## Post-Deployment Checklist

### 1. Get Load Balancer DNS Name

Choose one method:

- [ ] **Option A**: From AWS Console
  - Navigate to EC2 → Load Balancers
  - Find load balancer with name from outputs
  - Copy DNS name

- [ ] **Option B**: Via AWS CLI
  ```bash
  aws elbv2 describe-load-balancers \
    --names <vault_load_balancer_name> \
    --region <your-region> \
    --query 'LoadBalancers[0].DNSName' \
    --output text
  ```
  - Record load balancer DNS: `________________`

### 2. Configure DNS

- [ ] Access your DNS provider/manager
- [ ] Create new DNS record with these settings:
  - **Type**: CNAME (or ALIAS if Route 53)
  - **Name**: Your Vault FQDN (e.g., `vault.example.com`)
  - **Value**: Load balancer DNS name from step 1
  - **TTL**: 300 seconds (5 minutes)
- [ ] Save DNS record
- [ ] Wait for DNS propagation (usually 1-5 minutes)
- [ ] Verify DNS resolution:
  ```bash
  dig <your-vault-fqdn>
  # or
  nslookup <your-vault-fqdn>
  ```

### 3. Establish Network Connectivity to Vault

**If using INTERNAL load balancer** (default), choose one method:

- [ ] **Option A**: Launch Bastion Host
  - Launch EC2 instance in public subnet
  - Install Vault CLI on bastion
  - SSH to bastion host
  - Test connectivity from bastion

- [ ] **Option B**: AWS Systems Manager Session Manager
  - Find a Vault instance ID in AWS Console
  - Run: `aws ssm start-session --target <instance-id> --region <region>`
  - Test local access: `export VAULT_ADDR="https://127.0.0.1:8200"`

- [ ] **Option C**: VPN/Direct Connect
  - Ensure VPN connection to VPC is established
  - Test connectivity to Vault FQDN

**If using EXTERNAL load balancer**, verify your IP can reach the endpoint:
- [ ] Test from your local machine: `curl -k https://<vault-fqdn>:8200/v1/sys/health`

### 4. Initialize Vault Cluster

**⚠️ CRITICAL: Only perform initialization ONCE per cluster!**

- [ ] Set Vault address:
  ```bash
  export VAULT_ADDR="https://<your-vault-fqdn>:8200"
  ```

- [ ] Initialize Vault:
  ```bash
  vault operator init
  ```

- [ ] **Save unseal keys and root token SECURELY**:
  - [ ] Unseal Key 1: `________________` (saved securely)
  - [ ] Unseal Key 2: `________________` (saved securely)
  - [ ] Unseal Key 3: `________________` (saved securely)
  - [ ] Unseal Key 4: `________________` (saved securely)
  - [ ] Unseal Key 5: `________________` (saved securely)
  - [ ] Initial Root Token: `________________` (saved securely)

- [ ] Store keys in secure location:
  - [ ] Password manager (1Password, LastPass, etc.)
  - [ ] Encrypted file in secure storage
  - [ ] Hardware security module
  - [ ] Team secrets vault

  **DO NOT** store in plaintext, email, or unencrypted files!

### 5. Verify Cluster Status

- [ ] Check Vault status:
  ```bash
  vault status
  ```

- [ ] Verify these values in output:
  - [ ] `Sealed: false` (auto-unsealed via AWS KMS)
  - [ ] `HA Enabled: true`
  - [ ] `HA Mode: active` or `standby`

- [ ] Login with root token:
  ```bash
  vault login <root-token>
  ```

- [ ] List cluster members:
  ```bash
  vault operator raft list-peers
  ```

- [ ] Confirm you see all 6 nodes (or your configured count)

### 6. Basic Vault Configuration

- [ ] Enable audit logging:
  ```bash
  vault audit enable file file_path=/opt/vault/audit/audit.log
  ```

- [ ] Create admin policy:
  ```bash
  vault policy write admin - <<EOF
  path "*" {
    capabilities = ["create", "read", "update", "delete", "list", "sudo"]
  }
  EOF
  ```

- [ ] Enable authentication method (choose one):
  - [ ] Userpass: `vault auth enable userpass`
  - [ ] LDAP: `vault auth enable ldap`
  - [ ] OIDC: `vault auth enable oidc`
  - [ ] Other: `vault auth enable <method>`

- [ ] Create initial admin user(s)

- [ ] Test Vault UI access:
  - Navigate to: `https://<your-vault-fqdn>:8200/ui`
  - Login with root token
  - Verify UI loads correctly

## Security Hardening Checklist

- [ ] Rotate or revoke root token (after configuring other auth methods)
- [ ] Enable MFA for administrative accounts
- [ ] Review and restrict security group rules if needed
- [ ] Enable AWS CloudTrail for API auditing
- [ ] Configure AWS Config for compliance
- [ ] Enable AWS GuardDuty for threat detection
- [ ] Document emergency access procedures

## Operational Readiness Checklist

### Monitoring Setup

- [ ] Configure CloudWatch alarms for:
  - [ ] EC2 instance health checks
  - [ ] ALB healthy target count (alert if < 3)
  - [ ] ALB 4xx/5xx error rates
  - [ ] EBS volume metrics
  - [ ] NAT Gateway packet loss

- [ ] Set up log aggregation (optional but recommended)
- [ ] Configure Vault telemetry/metrics collection (optional)
- [ ] Set up alerting destination (PagerDuty, Slack, email, etc.)

### Backup and DR

- [ ] **Optional**: Configure automated Raft snapshots
  - [ ] Create S3 bucket for snapshots
  - [ ] Add `vault_snapshots_bucket_arn` to Terraform variables
  - [ ] Run `terraform apply` to update configuration
  - [ ] Configure snapshot schedule in Vault

- [ ] Perform test backup:
  ```bash
  vault operator raft snapshot save test-backup.snap
  ```

- [ ] Verify backup file was created successfully

- [ ] Document disaster recovery procedures:
  - [ ] How to restore from snapshot
  - [ ] Emergency contact information
  - [ ] Escalation procedures

### Documentation

- [ ] Document deployment architecture for your team
- [ ] Document access procedures (how to connect to Vault)
- [ ] Create runbooks for common operations:
  - [ ] Adding new users
  - [ ] Rotating certificates
  - [ ] Updating Vault version
  - [ ] Troubleshooting common issues
- [ ] Share documentation with operations team
- [ ] Schedule knowledge transfer session

## Compliance Checklist (If Applicable)

- [ ] Review applicable compliance requirements (SOC 2, ISO 27001, PCI DSS, etc.)
- [ ] Enable required audit logs
- [ ] Verify encryption settings meet compliance standards
- [ ] Document security controls implemented
- [ ] Prepare evidence for compliance audit
- [ ] Schedule compliance review

## Post-Deployment Validation

### Functional Testing

- [ ] Test API access from application/client locations
- [ ] Verify TLS certificate is valid and trusted
- [ ] Test secret creation and retrieval
- [ ] Verify auto-unseal is working (check instance restart)
- [ ] Test load balancer failover (optional but recommended)

### Performance Testing

- [ ] Measure API response times
- [ ] Test with expected load patterns
- [ ] Verify cluster handles requests correctly

### Security Testing

- [ ] Verify Vault is not accessible from unintended locations
- [ ] Confirm security group rules are correctly applied
- [ ] Test authentication methods work as expected
- [ ] Verify audit logs are being generated

## Handoff Checklist

Before considering deployment complete:

- [ ] All stakeholders notified of deployment
- [ ] Access credentials shared with appropriate team members
- [ ] Documentation uploaded to team wiki/knowledge base
- [ ] Monitoring and alerting configured
- [ ] On-call team briefed on Vault operations
- [ ] Emergency procedures documented and tested
- [ ] Deployment marked as production-ready

---

## Quick Reference

Use these values for your deployment (fill in during deployment):

**Configuration**:
- Organization: `________________`
- Workspace: `________________`
- AWS Region: `________________`
- Vault FQDN: `________________`
- VPC CIDR: `________________`

**Endpoints**:
- Vault API: `https://<vault-fqdn>:8200`
- Vault UI: `https://<vault-fqdn>:8200/ui`

**Resources Created**:
- VPC ID: `________________`
- KMS Key ARN: `________________`
- Load Balancer Name: `________________`

**Required Variables** (must be added to HCP Terraform workspace):
- `vault_fqdn` (string, sensitive)
- `vault_license` (string, sensitive)
- `vault_tls_cert` (string, sensitive)
- `vault_tls_key` (string, sensitive)
- `vault_ca_bundle` (string, sensitive)

**Support Resources**:
- [Vault Documentation](https://developer.hashicorp.com/vault)
- [HVD Module](https://registry.terraform.io/modules/hashicorp/vault-enterprise-hvd/aws)
- [HashiCorp Discuss](https://discuss.hashicorp.com/c/vault)
- [GitHub Issues](https://github.com/hashicorp/terraform-aws-vault-enterprise-hvd/issues)

---

**Note**: Print this checklist or use it digitally to track your progress through the deployment process. Check off items as completed to ensure nothing is missed.
