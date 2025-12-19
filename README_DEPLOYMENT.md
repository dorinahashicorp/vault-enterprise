# Vault Enterprise HVD on AWS - Terraform Configuration

This Terraform configuration deploys Vault Enterprise on AWS following HashiCorp Validated Design (HVD) patterns.

## Deployment Workflow

The deployment requires **2 simple steps**:

### Step 1: Create Secrets Manager Secrets (Manual, Outside Terraform)

Before running Terraform, you must create 4 secrets in AWS Secrets Manager with your actual certificate and license content.

```bash
# Create license secret
aws secretsmanager create-secret \
  --name vault-license \
  --secret-string file://your-license.hclic \
  --description "Vault Enterprise license"

# Create TLS certificate secret
aws secretsmanager create-secret \
  --name vault-tls-cert \
  --secret-string file://your-cert.pem \
  --description "Vault TLS certificate"

# Create TLS private key secret
aws secretsmanager create-secret \
  --name vault-tls-key \
  --secret-string file://your-key.pem \
  --description "Vault TLS private key"

# Create CA certificate secret
aws secretsmanager create-secret \
  --name vault-ca-cert \
  --secret-string file://your-ca.pem \
  --description "Vault CA certificate"
```

Note the ARNs of the secrets you just created - you'll need them in Step 2.

### Step 2: Run Terraform Apply

```bash
# Initialize Terraform
terraform init

# Create terraform.tfvars with:
# - Prerequisites outputs (VPC ID, subnet IDs, KMS key ARN)
# - Secret ARNs (from Step 1)
# - Vault configuration (version, instance count, FQDN, etc.)
# See: terraform.tfvars.example for template

# Review what will be created
terraform plan

# Deploy Vault Enterprise
terraform apply
```

That's it! Terraform will:
1. Create VPC, subnets, NAT Gateways, route tables, KMS key
2. Deploy Vault Enterprise using the official HVD module
3. Configure auto-unseal, networking, load balancer, and IAM

---

## Architecture Overview

The deployment consists of two phases managed by separate Terraform files:

1. **Prerequisites** (automatically managed by `terraform apply`) - Creates VPC, KMS, networking
2. **Vault Enterprise** (automatically managed by `terraform apply`) - Deploys cluster using prerequisites

This architecture provides:
- **Clear separation of concerns**: Infrastructure vs. application
- **Reusability**: One VPC can support multiple Vault deployments
- **Safety**: Official HVD module is never modified
- **Simplicity**: Single `terraform apply` handles both phases

## Phase 1: Prerequisite Infrastructure

### What Gets Created

The Terraform configuration automatically creates:

- **VPC**: A VPC with CIDR block `10.0.0.0/16` (customizable)
- **Public Subnets**: 3 public subnets (one per AZ) for load balancer
- **Private Subnets**: 3 private subnets (one per AZ) for Vault EC2 instances
- **Internet Gateway**: For public subnet routing
- **NAT Gateways**: One per public subnet for private subnet egress (for package updates)
- **Route Tables**: Separate routing for public and private subnets
- **KMS Key**: For Vault auto-unseal encryption

### Network Architecture

```
Internet
    ↓
[Internet Gateway] → [Public Subnets (3 AZs)]
    ↓
[NAT Gateways (3)] → [Private Subnets (3 AZs)]
    ↓
[Vault Instances + Load Balancer]
```

### Resource Dependencies

All resource ordering is automatic - Terraform handles dependencies based on resource references:

```
aws_vpc.main
  ├── aws_internet_gateway.main
  │   ├── aws_nat_gateway.main[0,1,2]
  │   │   ├── aws_eip.nat[0,1,2]
  │   │   └── aws_subnet.public[0,1,2]
  │   └── aws_route_table.public
  │       └── aws_route_table_association.public[0,1,2]
  │
  ├── aws_subnet.private[0,1,2]
  │   └── aws_route_table.private[0,1,2]
  │       └── aws_route_table_association.private[0,1,2]
  │
  └── aws_kms_key.vault
      └── aws_kms_alias.vault
```

## Phase 2: Vault Enterprise Deployment

### What Gets Created

The official HVD module creates:

- **Launch Template**: EC2 configuration for Vault instances
- **Auto Scaling Group**: Manages Vault instance group (scales 1-5 instances)
- **Network Load Balancer**: Distributes traffic across Vault instances
- **Target Group**: Health checks for load balancer
- **Security Groups**: Controls network access to Vault and load balancer
- **IAM Role & Instance Profile**: Permissions for EC2 to access KMS and Secrets Manager
- **EC2 Instances**: Running Vault Enterprise (auto-launched by ASG)

The module retrieves certificates and license from the Secrets Manager secrets you created in Step 1.

## File Structure

```
.
├── prerequisites.tf              # VPC, subnets, NAT, KMS - auto-run by apply
├── prerequisites-variables.tf    # Configuration for prerequisites (VPC CIDR, tags)
├── prerequisites-outputs.tf      # Outputs of prerequisites infrastructure
├── main.tf                       # Vault Enterprise HVD module
├── variables.tf                  # Variables for Vault module (inherited from prerequisites)
├── outputs.tf                    # Outputs of Vault cluster
├── terraform.tf                  # Terraform version and provider requirements
├── versions.tf                   # Detailed provider versions
├── terraform.tfvars.example      # Example configuration (rename to terraform.tfvars)
├── README_DEPLOYMENT.md          # This file
├── DEPENDENCY_MAP.md             # Detailed dependency documentation
└── AWS_SETUP_STEPS.md            # Manual AWS setup reference
```

## Configuration Variables

### What Gets Created

The main `main.tf` configuration deploys:

- **Auto Scaling Group**: 3 Vault nodes (configurable) with automatic launch
- **Launch Template**: EC2 configuration with bootstrap script
- **Security Groups**: For Vault API and SSH access
- **Network Load Balancer**: Internal load balancer for Vault API
- **IAM Roles**: Instance profiles with permissions for KMS and Secrets Manager
- **Route53 Health Checks**: For load balancer health monitoring

### Resource Dependencies

The Vault module explicitly depends on prerequisites resources:

```
module.vault (hashicorp/terraform-aws-vault-enterprise-hvd)
  ├── Depends on: aws_vpc.main (referenced via var.vpc_id)
  ├── Depends on: aws_subnet.private[*] (referenced via var.vault_subnet_ids)
  ├── Depends on: aws_subnet.public[*] (referenced via var.lb_subnet_ids)
  ├── Depends on: aws_kms_key.vault (referenced via var.kms_key_id)
  │   └── Implicitly: aws_nat_gateway.main[*] (subnets reference route tables)
  └── Depends on: aws_secretsmanager_secret.vault_* (referenced via var.*_secret_arn)
      └── Depends on: aws_secretsmanager_secret_version.vault_*
```

These dependencies are documented in the comments but are **implicit** because Terraform infers them from the variable references. The module will fail to create if prerequisites are missing.

### Step 3: Configure Vault Module

Create `terraform.tfvars` using the prerequisites outputs:

```bash
# Get all prerequisite outputs at once
terraform output -json prerequisites_summary
```

## Configuration Variables

### Prerequisites Variables (from `terraform.tfvars`)

The prerequisites configuration accepts these input variables:

| Variable | Type | Default | Description |
|----------|------|---------|-------------|
| `aws_region` | string | `us-east-1` | AWS region to deploy to |
| `vpc_cidr` | string | `10.0.0.0/16` | VPC CIDR block (must be valid CIDR) |
| `friendly_name_prefix` | string | `vault` | Prefix for resource names (max 20 chars) |
| `resource_tags` | map(string) | `{}` | Tags to apply to all resources |

### Vault Module Variables (from `terraform.tfvars`)

| Variable | Type | Required | Description |
|----------|------|----------|-------------|
| `vpc_id` | string | Yes | VPC ID from prerequisites |
| `vault_subnet_ids` | list(string) | Yes | Private subnet IDs from prerequisites (exactly 3) |
| `lb_subnet_ids` | list(string) | Yes | Public subnet IDs from prerequisites (exactly 3) |
| `kms_key_id` | string | Yes | KMS key ARN from prerequisites |
| `vault_license_secret_arn` | string | Yes | ARN of license secret (created in Step 1) |
| `vault_tls_cert_secret_arn` | string | Yes | ARN of TLS cert secret (created in Step 1) |
| `vault_tls_key_secret_arn` | string | Yes | ARN of TLS key secret (created in Step 1) |
| `vault_ca_cert_secret_arn` | string | Yes | ARN of CA cert secret (created in Step 1) |
| `friendly_name_prefix` | string | No | Prefix for Vault resources (default: `vault`) |
| `vault_version` | string | No | Vault Enterprise version (default: `1.17.0`) |
| `node_count` | number | No | Number of Vault nodes (default: `3`) |
| `instance_type` | string | No | EC2 instance type (default: `t3.large`) |
| `vault_fqdn` | string | No | FQDN for Vault (for TLS certificate validation) |
| `ingress_cidr_blocks` | list(string) | No | CIDR blocks for API access (default: `["0.0.0.0/0"]`) |
| `ingress_ssh_cidr_blocks` | list(string) | No | CIDR blocks for SSH access (default: `[]` - disabled) |
| `resource_tags` | map(string) | No | Tags for all Vault resources |

## Deployment Steps (Detailed)

### Step 1: Create Secrets in AWS Secrets Manager

**Before running Terraform**, create 4 secrets with your actual content:

```bash
# Set variables for your files
export LICENSE_FILE="path/to/your/license.hclic"
export CERT_FILE="path/to/your/cert.pem"
export KEY_FILE="path/to/your/key.pem"
export CA_FILE="path/to/your/ca.pem"
export AWS_REGION="us-east-1"  # Adjust to your region

# Create secrets
aws secretsmanager create-secret \
  --region $AWS_REGION \
  --name vault-license \
  --secret-string file://$LICENSE_FILE

aws secretsmanager create-secret \
  --region $AWS_REGION \
  --name vault-tls-cert \
  --secret-string file://$CERT_FILE

aws secretsmanager create-secret \
  --region $AWS_REGION \
  --name vault-tls-key \
  --secret-string file://$KEY_FILE

aws secretsmanager create-secret \
  --region $AWS_REGION \
  --name vault-ca-cert \
  --secret-string file://$CA_FILE

# Note the ARNs returned - you'll need them next
```

### Step 2: Prepare terraform.tfvars

Create `terraform.tfvars` in your Terraform working directory:

```hcl
# AWS Region
aws_region = "us-east-1"

# VPC Configuration (for prerequisites)
vpc_cidr                = "10.0.0.0/16"
friendly_name_prefix    = "vault"

# Vault Infrastructure (from prerequisites)
vpc_id = "vpc-xxxxxxxxx"  # Get from: terraform output vpc_id
vault_subnet_ids = [
  "subnet-xxxxxxxxx",
  "subnet-yyyyyyyyy",
  "subnet-zzzzzzzzz"
]  # Get from: terraform output vault_subnet_ids

lb_subnet_ids = [
  "subnet-aaaaaaaaa",
  "subnet-bbbbbbbbb",
  "subnet-ccccccccc"
]  # Get from: terraform output lb_subnet_ids

kms_key_id = "arn:aws:kms:us-east-1:123456789012:key/..."  # Get from: terraform output kms_key_arn

# Vault Secrets (from Step 1)
vault_license_secret_arn  = "arn:aws:secretsmanager:us-east-1:123456789012:secret:vault-license-xxxxx"
vault_tls_cert_secret_arn = "arn:aws:secretsmanager:us-east-1:123456789012:secret:vault-tls-cert-xxxxx"
vault_tls_key_secret_arn  = "arn:aws:secretsmanager:us-east-1:123456789012:secret:vault-tls-key-xxxxx"
vault_ca_cert_secret_arn  = "arn:aws:secretsmanager:us-east-1:123456789012:secret:vault-ca-cert-xxxxx"

# Vault Configuration
vault_version = "1.17.0"
node_count    = 3
instance_type = "t3.large"
vault_fqdn    = "vault.example.com"

# Network Access
ingress_cidr_blocks     = ["0.0.0.0/0"]
ingress_ssh_cidr_blocks = []  # Leave empty to disable SSH

# Tags
resource_tags = {
  Environment = "production"
  ManagedBy   = "terraform"
  CostCenter  = "engineering"
}
```

### Step 3: Deploy with Terraform

```bash
# Initialize Terraform (downloads providers and modules)
terraform init

# Review what will be created
terraform plan

# Deploy the infrastructure and Vault cluster
terraform apply

# Get the load balancer endpoint
terraform output vault_load_balancer_dns
```

After `terraform apply` completes, Terraform will:

1. ✅ Create VPC, subnets, NAT Gateways, KMS key
2. ✅ Deploy 3 Vault EC2 instances with auto-unseal configured
3. ✅ Configure load balancer for high availability
4. ✅ Set up IAM permissions for KMS and Secrets Manager access

The Vault instances will automatically:
- Retrieve certificates and license from Secrets Manager
- Initialize with KMS auto-unseal
- Join the cluster together
- Register with the load balancer

### Step 4: Initialize and Unseal Vault

Once deployment is complete and instances are healthy (check in EC2 console):

```bash
# Get the load balancer DNS name
VAULT_ADDR=$(terraform output -raw vault_load_balancer_dns)

# Initialize Vault (generates root token and unseal keys)
vault operator init \
  -key-shares=5 \
  -key-threshold=3 \
  -address="https://$VAULT_ADDR"

# Unseal each Vault node with 3 of the 5 keys
vault operator unseal -address="https://$VAULT_ADDR"
# (Repeat for each node or use raft auto-unseal if configured)
```

## Troubleshooting

### Terraform apply fails with "Required variable not set"

**Cause**: Missing values in `terraform.tfvars`

**Solution**: Ensure all required variables are populated. Check against `terraform.tfvars.example`.

### Secrets Manager secret not found error during Vault bootstrap

**Cause**: Secrets created in wrong AWS region or wrong secret names

**Solution**:
- Verify secrets exist: `aws secretsmanager list-secrets --region us-east-1`
- Verify secret contents are valid (not empty): `aws secretsmanager get-secret-value --secret-id vault-license`
- Ensure secret names exactly match what's in terraform.tfvars

### EC2 instances not reaching healthy state

**Cause**: Load balancer health checks failing (likely bootstrap script issues)

**Solution**:
1. SSH to an instance: `aws ssm start-session --target <instance-id>`
2. Check bootstrap logs: `tail -f /var/log/user-data.log`
3. Verify Vault is running: `systemctl status vault`
4. Check Vault logs: `/vault/log/*`

### "cannot retrieve license from Secrets Manager" error

**Cause**: License file content in Secrets Manager is invalid or empty

**Solution**:
- Verify license file is valid: `cat your-license.hclic`
- Update secret: `aws secretsmanager put-secret-value --secret-id vault-license --secret-string file://your-license.hclic`
- Wait for instances to health-check and try again

## Cleanup

To destroy all resources (careful!):

```bash
# Remove Vault cluster and infrastructure
terraform destroy

# Remove Secrets Manager secrets
aws secretsmanager delete-secret --secret-id vault-license
aws secretsmanager delete-secret --secret-id vault-tls-cert
aws secretsmanager delete-secret --secret-id vault-tls-key
aws secretsmanager delete-secret --secret-id vault-ca-cert
```

**Note**: Secrets Manager has a recovery window (7 days) before permanent deletion.

## Security Considerations

1. **Never commit `terraform.tfvars` to version control** - it contains secret ARNs and sensitive configuration
2. **Restrict access to Secrets Manager** - use IAM policies to limit who can read certificates/license
3. **Rotate TLS certificates** - plan for certificate renewal before expiration
4. **Use strong Vault policies** - configure RBAC after initialization
5. **Enable audit logging** - configure Vault audit backend for compliance
6. **Restrict CIDR blocks** - change `ingress_cidr_blocks` from `0.0.0.0/0` in production

## Next Steps

After successful deployment:

1. **Initialize Vault**: Run `vault operator init` to get root token and unseal keys
2. **Configure authentication methods**: Enable auth methods (LDAP, JWT, etc.)
3. **Set up secret engines**: Configure KV, PKI, database engines
4. **Create policies**: Define RBAC policies for your organization
5. **Monitor**: Set up CloudWatch alarms and audit logging
6. **Backup state**: Store Terraform state securely (use Terraform Cloud or S3 backend)
## References

- [HashiCorp Vault Enterprise Documentation](https://developer.hashicorp.com/vault/docs)
- [HashiCorp Validated Design (HVD) for Vault on AWS](https://developer.hashicorp.com/vault/tutorials/aws)
- [Terraform AWS Vault Enterprise HVD Module](https://registry.terraform.io/modules/hashicorp/terraform-aws-vault-enterprise-hvd/aws/latest)
- [AWS Secrets Manager Documentation](https://docs.aws.amazon.com/secretsmanager/)
- [AWS KMS Documentation](https://docs.aws.amazon.com/kms/)
- [AWS VPC Documentation](https://docs.aws.amazon.com/vpc/)

- HashiCorp Vault Enterprise HVD Module: https://github.com/hashicorp/terraform-aws-vault-enterprise-hvd
- Vault Documentation: https://www.vaultproject.io/docs
- AWS VPC Guide: https://docs.aws.amazon.com/vpc/
