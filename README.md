# Vault Enterprise Deployment on AWS

Terraform configuration for deploying HashiCorp Vault Enterprise on AWS using the [HashiCorp Validated Design (HVD)](https://registry.terraform.io/modules/hashicorp/vault-enterprise-hvd/aws/latest).

> **⚠️ SECURITY NOTICE**: This configuration includes settings optimized for **testing and evaluation purposes**. Before using in production, review and harden security settings as outlined in the [Security Considerations](#security-considerations) section.

## Architecture Overview

This configuration deploys a complete, high-availability Vault Enterprise cluster with:

- **High Availability**: 6 Vault nodes across 3 availability zones (configurable)
- **Auto-Unseal**: AWS KMS-based automatic unsealing
- **Storage Backend**: Integrated Raft consensus storage
- **Load Balancing**: Internal or external AWS Application Load Balancer
- **TLS**: End-to-end encryption with custom certificates
- **Auto Scaling**: Automatic node replacement and health monitoring
- **Complete Network Infrastructure**: VPC, subnets, NAT gateways, and VPC endpoints
- **Secrets Management**: Vault license and TLS certificates stored in AWS Secrets Manager

## Infrastructure Components

### Automated Infrastructure Creation

The Terraform configuration automatically provisions:

#### Network Infrastructure
- **VPC**: Dedicated VPC with configurable CIDR (default: 10.0.0.0/16)
- **Subnets**: 3 private and 3 public subnets across different availability zones
- **NAT Gateways**: One per AZ for high availability
- **Internet Gateway**: For public subnet connectivity
- **VPC Endpoints**: S3 (gateway), Secrets Manager, KMS, and EC2 (interface endpoints)

#### Security
- **KMS Key**: Dedicated AWS KMS key for auto-unseal with automatic rotation
- **AWS Secrets Manager**: Stores Vault license and TLS certificates
- **Security Groups**: Configured for Vault instances, load balancer, and VPC endpoints
- **Encrypted EBS Volumes**: All disks encrypted at rest

#### Compute
- **Auto Scaling Group**: Configurable number of EC2 instances across 3 AZs
- **Application Load Balancer**: Distributes traffic to Vault nodes
- **Launch Template**: Automated instance configuration

## Prerequisites

Before deploying, ensure you have:

1. **HCP Terraform Account**: Access to HCP Terraform (formerly Terraform Cloud)
2. **AWS Credentials**: Valid AWS access keys with appropriate permissions
3. **Vault Enterprise License**: A valid `.hclic` license file
4. **TLS Certificates**:
   - TLS certificate (PEM format, including full chain)
   - TLS private key (PEM format)
   - CA certificate bundle (PEM format)
5. **DNS Domain**: A domain where you can create DNS records (e.g., `vault.example.com`)

### Required AWS Permissions

Your AWS credentials need permissions to create:
- VPC and networking resources
- EC2 instances and Auto Scaling Groups
- Application Load Balancers
- KMS keys
- AWS Secrets Manager secrets
- IAM roles and policies

## Setup Instructions

### Step 1: Configure HCP Terraform Workspace

1. **Create or access HCP Terraform workspace**:
   - Log into HCP Terraform at https://app.terraform.io
   - Create a new workspace or use an existing one
   - Choose VCS workflow (recommended) or CLI workflow
   - Note your organization name and workspace name

2. **Update Terraform backend configuration**:

   Edit `terraform.tf` and update the `cloud` block:
   ```hcl
   cloud {
     organization = "YOUR_ORGANIZATION_NAME"  # Change this

     workspaces {
       name = "YOUR_WORKSPACE_NAME"  # Change this
     }
   }
   ```

3. **Configure AWS credentials as environment variables**:
   - Go to your workspace → Variables
   - Add environment variables:
     - `AWS_ACCESS_KEY_ID` (sensitive)
     - `AWS_SECRET_ACCESS_KEY` (sensitive)
     - Optional: `AWS_SESSION_TOKEN` (if using temporary credentials)

### Step 2: Configure Terraform Variables

Add the following variables to your HCP Terraform workspace:

#### Required Variables (Sensitive)

All of these should be marked as **Sensitive** in HCP Terraform:

| Variable | Type | Description |
|----------|------|-------------|
| `vault_fqdn` | string | Fully qualified domain name (e.g., `vault.example.com`) |
| `vault_license` | string | Complete content of your `.hclic` file |
| `vault_tls_cert` | string | TLS certificate in PEM format (include full chain) |
| `vault_tls_key` | string | TLS private key in PEM format |
| `vault_ca_bundle` | string | CA certificate bundle in PEM format |

**How to add sensitive variables**:
1. Workspace → Variables → Add variable
2. Select "Terraform variable"
3. Enter variable name
4. Paste the entire file content
5. Check "Sensitive" checkbox
6. Click "Save variable"

#### Optional Variables (With Defaults)

These have sensible defaults but can be customized:

| Variable | Default | Description |
|----------|---------|-------------|
| `aws_region` | `us-east-1` | AWS region for deployment |
| `environment` | `prod` | Environment name tag |
| `resource_name_prefix` | `vault` | Prefix for AWS resource names |
| `vpc_cidr` | `10.0.0.0/16` | VPC CIDR block |
| `vault_version` | `1.18.2+ent` | Vault Enterprise version |
| `asg_node_count` | `6` | Number of Vault nodes (must be odd for Raft) |
| `vm_instance_type` | `m7i.large` | EC2 instance type (2 vCPU, 8 GB RAM) |
| `load_balancing_scheme` | `INTERNAL` | `INTERNAL` (private) or `EXTERNAL` (public) |
| `kms_deletion_window` | `10` | Days before KMS key permanent deletion |

See `terraform.tfvars.example` for all available configuration options.

### Step 3: Deploy Infrastructure

1. **Initialize Terraform**:
   ```bash
   terraform init
   ```
   This connects to your HCP Terraform workspace and downloads required providers.

2. **Review the deployment plan**:
   ```bash
   terraform plan
   ```
   Review the ~40-50 resources that will be created.

3. **Apply the configuration**:
   ```bash
   terraform apply
   ```
   Type `yes` when prompted. Deployment takes approximately 10-15 minutes.

4. **Capture outputs**:
   ```bash
   terraform output
   ```
   Save these outputs for the next steps.

### Step 4: Configure DNS

After deployment, create a DNS record pointing to your Vault cluster:

1. **Get the load balancer DNS name**:
   - From terraform outputs: `vault_load_balancer_name`
   - Or from AWS Console: EC2 → Load Balancers
   - Or via AWS CLI:
     ```bash
     aws elbv2 describe-load-balancers \
       --names <load_balancer_name> \
       --region <your-region> \
       --query 'LoadBalancers[0].DNSName' \
       --output text
     ```

2. **Create DNS record**:
   - **Type**: CNAME (or ALIAS if using Route 53)
   - **Name**: Your vault FQDN (e.g., `vault.example.com`)
   - **Value**: Load balancer DNS name from step 1
   - **TTL**: 300 seconds (5 minutes)

3. **Verify DNS propagation**:
   ```bash
   dig vault.example.com
   # or
   nslookup vault.example.com
   ```

### Step 5: Access Your Vault Cluster

#### Important: Internal vs External Load Balancer

- **INTERNAL** (default): Only accessible from within the VPC
  - Requires VPN, Direct Connect, or bastion host access
  - Recommended for production deployments

- **EXTERNAL**: Publicly accessible
  - Accessible from the internet
  - Still requires valid TLS certificates
  - Ensure security groups restrict access appropriately

#### Connecting to Internal Load Balancer

If using `INTERNAL` load balancer, you need network access to the VPC. Options:

**Option A: Launch a bastion host**
```bash
# Launch an EC2 instance in a public subnet
# Install Vault CLI on the bastion
# SSH to bastion and access Vault from there
```

**Option B: Use AWS Systems Manager Session Manager**
```bash
# Connect to a Vault instance
aws ssm start-session --target <instance-id> --region <your-region>

# Once connected, test local access
export VAULT_ADDR="https://127.0.0.1:8200"
vault status
```

**Option C: VPN/Direct Connect**
- Configure AWS Client VPN or use existing VPN connection to VPC

### Step 6: Initialize Vault

Once you have network connectivity:

1. **Set the Vault address**:
   ```bash
   export VAULT_ADDR="https://vault.example.com:8200"

   # Or use the load balancer DNS directly
   # export VAULT_ADDR="https://internal-vault-xxx.elb.amazonaws.com:8200"
   ```

2. **Initialize the Vault cluster** (only run once!):
   ```bash
   vault operator init
   ```

3. **Save the output securely**:
   ```
   Unseal Key 1: <key1>
   Unseal Key 2: <key2>
   Unseal Key 3: <key3>
   Unseal Key 4: <key4>
   Unseal Key 5: <key5>

   Initial Root Token: <token>
   ```

   **CRITICAL**: Store these in a secure location (password manager, secure vault). You cannot recover them if lost!

4. **Verify cluster status**:
   ```bash
   vault status
   ```

   Expected output:
   ```
   Sealed: false  (auto-unsealed via AWS KMS)
   HA Enabled: true
   HA Mode: active
   ```

5. **Check cluster members**:
   ```bash
   vault login <root-token>
   vault operator raft list-peers
   ```

### Step 7: Access Vault UI

Navigate to: `https://vault.example.com:8200/ui`

Login with the root token from initialization.

## Post-Deployment Configuration

### Enable Audit Logging

```bash
export VAULT_TOKEN="<your-root-token>"

vault audit enable file file_path=/opt/vault/audit/audit.log
```

### Configure Authentication

```bash
# Example: Enable userpass authentication
vault auth enable userpass

# Create an admin user
vault write auth/userpass/users/admin \
  password="secure-password" \
  policies="admin"
```

### Create Admin Policy

```bash
vault policy write admin - <<EOF
# Full access to all paths
path "*" {
  capabilities = ["create", "read", "update", "delete", "list", "sudo"]
}
EOF
```

### Setup Automated Snapshots (Optional)

1. Create an S3 bucket:
   ```bash
   aws s3 mb s3://vault-snapshots-mycompany --region us-east-1
   ```

2. Add bucket ARN to Terraform variables:
   ```
   vault_snapshots_bucket_arn = "arn:aws:s3:::vault-snapshots-mycompany"
   ```

3. Run `terraform apply`

4. Configure snapshot automation:
   ```bash
   vault write sys/storage/raft/snapshot-auto/config \
     interval="1h" \
     retain=24 \
     storage_type="aws-s3" \
     aws_s3_bucket="vault-snapshots-mycompany" \
     aws_s3_region="us-east-1"
   ```

## Maintenance Operations

### Rotating TLS Certificates

1. Update certificate variables in HCP Terraform workspace:
   - `vault_tls_cert`
   - `vault_tls_key`
   - `vault_ca_bundle`

2. Run `terraform apply`

3. Terraform updates AWS Secrets Manager secrets

4. Auto Scaling Group performs rolling updates to replace instances

### Rotating Vault License

1. Update `vault_license` variable in HCP Terraform workspace
2. Run `terraform apply`
3. New license deployed with instance refresh

### Updating Vault Version

1. Update `vault_version` variable (e.g., `1.19.0+ent`)
2. Run `terraform apply`
3. Auto Scaling Group performs rolling updates

### Scaling the Cluster

**Horizontal scaling** (add/remove nodes):
```hcl
asg_node_count = 9  # Must be odd number for Raft
```

**Vertical scaling** (larger instances):
```hcl
vm_instance_type = "m7i.xlarge"  # 4 vCPU, 16 GB RAM
```

Run `terraform apply` after changes.

## Cost Optimization

This deployment includes several cost optimizations:

- **VPC Endpoints**: Reduce NAT Gateway data transfer costs
- **GP3 EBS volumes**: Better price-to-performance than GP2
- **Right-sized instances**: m7i.large balances performance and cost
- **Regional optimization**: Deploy in cost-effective regions

### Estimated Monthly Costs (us-east-1)

- **EC2 Instances**: 6 × m7i.large × $0.1008/hr = ~$436/month
- **EBS Volumes**: 6 × 180 GB GP3 = ~$108/month
- **Application Load Balancer**: ~$23/month
- **NAT Gateways**: 3 × $32.40 = ~$97/month
- **Secrets Manager**: 4 secrets × $0.40 = ~$2/month
- **VPC Endpoints**: 3 interface endpoints = ~$22/month
- **Data Transfer**: Variable (depends on usage)

**Total**: ~$688/month (excluding data transfer)

## Security Considerations

### ⚠️ Current Configuration is for Testing/Evaluation

This deployment includes relaxed security settings for ease of testing and development. **DO NOT use in production without the following hardening steps:**

#### Settings That Must Be Changed for Production:

1. **Load Balancer Ingress (`main.tf:72`)**
   - **Current**: `net_ingress_vault_cidr_blocks = ["0.0.0.0/0"]` - Allows access from anywhere
   - **Production**: Restrict to specific IP ranges or VPN CIDR blocks
   ```hcl
   net_ingress_vault_cidr_blocks = ["10.0.0.0/8", "172.16.0.0/12"]  # Your corporate network ranges
   ```

2. **Load Balancer Scheme (`variables.tf:127`)**
   - **Current**: `default = "EXTERNAL"` - Public internet-facing load balancer
   - **Production**: Consider `INTERNAL` for private-only access or restrict ingress CIDR blocks
   ```hcl
   default = "INTERNAL"  # Or use EXTERNAL with strict CIDR restrictions
   ```

3. **Bastion Host SSH (`bastion.tf:35`)**
   - **Current**: `cidr_blocks = ["0.0.0.0/0"]` - Allows SSH from anywhere
   - **Production**: Restrict to your IP address or corporate network
   ```hcl
   cidr_blocks = ["YOUR_IP_ADDRESS/32"]  # Replace with your actual IP
   ```

4. **KMS Deletion Window (`secrets.tf:16`)**
   - **Current**: `recovery_window_in_days = 0` - Immediate deletion (testing only)
   - **Production**: Set to 7-30 days for recovery protection
   ```hcl
   recovery_window_in_days = 30  # Recommended for production
   ```

5. **Remove Bastion Host**
   - The bastion host (`bastion.tf`) is for initial setup only
   - Delete or comment out `bastion.tf` after Vault initialization
   - Use AWS Systems Manager Session Manager for emergency access instead

### Security Best Practices

#### During Deployment
- Mark all sensitive variables as "Sensitive" in HCP Terraform
- Store Vault license and certificates securely before adding to Terraform
- Review and restrict all security group rules before applying
- Use least-privilege IAM policies

#### Post-Deployment
- Rotate or revoke root token after configuring other auth methods
- Enable MFA for admin accounts
- Configure AWS CloudTrail for API auditing
- Set up AWS Config for compliance monitoring
- Enable AWS GuardDuty for threat detection
- Document disaster recovery procedures
- Implement regular Raft snapshots to S3
- Set up monitoring and alerting

#### Network Security
- Use internal load balancer for production (recommended)
- Keep Vault instances in private subnets only
- Restrict security group ingress to known CIDR ranges
- Use VPC endpoints to reduce internet exposure
- Ensure all traffic is encrypted with TLS
- Regularly rotate TLS certificates (90-day maximum with Let's Encrypt)

## Disaster Recovery

### Manual Snapshots

```bash
# Create snapshot
vault operator raft snapshot save backup-$(date +%Y%m%d-%H%M%S).snap

# Restore from snapshot
vault operator raft snapshot restore backup.snap
```

### Automated Snapshots

See "Setup Automated Snapshots" section above.

### Multi-Region DR

For production deployments:
1. Deploy secondary cluster in another region
2. Enable Vault Performance Replication (Enterprise feature)
3. Configure automated failover procedures

## Troubleshooting

### Cannot connect to Vault

**For INTERNAL load balancer**:
- Ensure you're connecting from within the VPC
- Verify security group rules allow port 8200 from your source
- Check DNS resolution
- Verify load balancer health checks are passing

### Vault nodes not joining cluster

```bash
# Check security groups
aws ec2 describe-security-groups \
  --filters "Name=tag:Name,Values=*vault*" \
  --region <your-region>

# Verify ports 8200 (API) and 8201 (cluster) are open between nodes
```

### Auto-unseal failing

```bash
# Verify KMS key exists
aws kms describe-key --key-id <kms-key-arn>

# Check IAM permissions on Vault instance role
# Vault instances need kms:Encrypt and kms:Decrypt permissions
```

### TLS certificate errors

```bash
# Verify certificate matches your FQDN
openssl s_client -connect vault.example.com:8200 -showcerts

# Check certificate chain is complete
openssl verify -CAfile ca-bundle.pem certificate.pem
```

### Secrets Manager issues

```bash
# Verify secrets were created
aws secretsmanager list-secrets \
  --filters Key=name,Values=vault \
  --region <your-region>
```

## Monitoring and Alerting

### Recommended CloudWatch Alarms

- EC2 instance health (StatusCheckFailed)
- ALB healthy target count (< 3)
- ALB 4xx/5xx error rates
- EBS volume performance metrics
- NAT Gateway packet loss

### Vault Telemetry

Configure Vault to send metrics to CloudWatch, DataDog, or other monitoring systems. See [Vault telemetry documentation](https://developer.hashicorp.com/vault/docs/configuration/telemetry).

## File Structure

```
.
├── README.md                    # This file
├── DEPLOYMENT_CHECKLIST.md      # Step-by-step deployment checklist
├── terraform.tf                 # Terraform and provider configuration
├── variables.tf                 # Variable definitions
├── terraform.tfvars.example     # Example variable values
├── main.tf                      # Vault HVD module configuration
├── infrastructure.tf            # VPC, networking, KMS resources
├── secrets.tf                   # AWS Secrets Manager configuration
├── outputs.tf                   # Output values
└── .gitignore                   # Git ignore rules
```

## Additional Resources

- [HashiCorp Vault Documentation](https://developer.hashicorp.com/vault)
- [Vault Enterprise HVD Module](https://registry.terraform.io/modules/hashicorp/vault-enterprise-hvd/aws)
- [Vault Reference Architecture](https://developer.hashicorp.com/vault/tutorials/day-one-raft/raft-reference-architecture)
- [Vault Deployment Guide](https://developer.hashicorp.com/vault/tutorials/day-one-raft/raft-deployment-guide)
- [AWS Well-Architected Framework](https://aws.amazon.com/architecture/well-architected/)

## Support

- **Module Issues**: [GitHub Issues](https://github.com/hashicorp/terraform-aws-vault-enterprise-hvd/issues)
- **Vault Questions**: [HashiCorp Discuss](https://discuss.hashicorp.com/c/vault)
- **Enterprise Support**: Contact your HashiCorp account team

## License

This Terraform configuration is provided as-is for deploying HashiCorp Vault Enterprise. Vault Enterprise requires a valid license from HashiCorp.
