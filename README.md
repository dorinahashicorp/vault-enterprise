# Vault Enterprise Deployment on AWS

This repository contains Terraform configuration for deploying HashiCorp Vault Enterprise on AWS using the [HashiCorp Validated Design (HVD)](https://registry.terraform.io/modules/hashicorp/vault-enterprise-hvd/aws/latest).

## Architecture

This configuration creates a complete, production-ready Vault Enterprise deployment with:

- **High Availability**: 6 Vault nodes across 3 availability zones
- **Auto-Unseal**: AWS KMS-based automatic unsealing
- **Storage Backend**: Integrated Raft storage
- **Load Balancing**: Internal AWS Application Load Balancer
- **TLS**: End-to-end encryption with custom certificates
- **Auto Scaling**: Automatic node replacement and health monitoring
- **Complete Network Infrastructure**: VPC, subnets, NAT gateways, and VPC endpoints
- **Automated Secrets Management**: Terraform creates AWS Secrets Manager secrets from HCP Terraform variables

## Infrastructure Components

The Terraform configuration automatically creates:

### Network Infrastructure
- **VPC**: Dedicated VPC with customizable CIDR (default: 10.0.0.0/16)
- **Subnets**: 3 private subnets and 3 public subnets across different AZs
- **NAT Gateways**: One per AZ for high availability
- **Internet Gateway**: For public subnet internet access
- **VPC Endpoints**: S3 (gateway), Secrets Manager, KMS, and EC2 (interface endpoints)

### Security
- **KMS Key**: Dedicated AWS KMS key for auto-unseal with automatic rotation
- **AWS Secrets Manager**: Automatically created from Terraform variables
- **Security Groups**: For Vault instances, load balancer, and VPC endpoints
- **Encrypted EBS Volumes**: All disks encrypted at rest

### Compute
- **Auto Scaling Group**: 6 EC2 instances (m7i.large) across 3 AZs
- **Application Load Balancer**: For distributing traffic to Vault nodes
- **Launch template**

## Prerequisites

### 1. HCP Terraform Workspace

You already have:
- ✅ HCP Terraform workspace named `vault-enterprise`
- ✅ AWS credentials configured as environment variables
- ✅ `vault_fqdn` variable set to `vault.infragoose.com`

### 2. Prepare Your Secrets

Have these files ready to add to HCP Terraform workspace variables:
- **Vault Enterprise License**: Your `.hclic` file
- **TLS Certificate**: Your certificate in PEM format (including full chain)
- **TLS Private Key**: Your private key in PEM format
- **CA Bundle**: Your CA certificate bundle in PEM format

## HCP Terraform Workspace Configuration

### Required Variables

Add these **sensitive** variables to your `vault-enterprise` workspace:

| Variable | Type | Description | How to Add |
|----------|------|-------------|------------|
| `vault_fqdn` | string | ✅ Already set | `vault.infragoose.com` |
| `vault_license` | string (sensitive) | Content of your `.hclic` file | Copy entire file content |
| `vault_tls_cert` | string (sensitive) | TLS certificate (PEM) | Copy entire cert file |
| `vault_tls_key` | string (sensitive) | TLS private key (PEM) | Copy entire key file |
| `vault_ca_bundle` | string (sensitive) | CA bundle (PEM) | Copy entire CA bundle |

**How to add sensitive variables in HCP Terraform:**
1. Go to your workspace → Variables
2. Click "Add variable"
3. Select "Terraform variable"
4. Enter variable name (e.g., `vault_license`)
5. Paste the entire file content into the value field
6. Check "Sensitive" checkbox
7. Click "Save variable"

### Optional Variables

| Variable | Default | Description |
|----------|---------|-------------|
| `aws_region` | `us-east-1` | AWS region |
| `environment` | `prod` | Environment name |
| `resource_name_prefix` | `vault` | Prefix for resource names |
| `vpc_cidr` | `10.0.0.0/16` | VPC CIDR block |
| `vault_version` | `1.18.2+ent` | Vault version |
| `asg_node_count` | `6` | Number of Vault nodes |
| `vm_instance_type` | `m7i.large` | EC2 instance type |
| `load_balancing_scheme` | `INTERNAL` | Load balancer type (INTERNAL or EXTERNAL) |
| `kms_deletion_window` | `10` | KMS key deletion window (days) |

## Deployment Steps

### 1. Initialize Terraform

```bash
terraform init
```

This will:
- Connect to your HCP Terraform workspace
- Download required providers and modules

### 2. Plan Deployment

```bash
terraform plan
```

Review the plan carefully. Terraform will create approximately 40-50 resources including:
- VPC, subnets, route tables, internet gateway, NAT gateways
- KMS key for auto-unseal
- AWS Secrets Manager secrets (from your HCP Terraform variables)
- VPC endpoints for AWS services
- Vault cluster (6 EC2 instances, ASG, ALB, security groups, IAM roles)

### 3. Apply Configuration

```bash
terraform apply
```

Type `yes` when prompted. The deployment will take approximately 10-15 minutes.

### 4. Verify Deployment

After deployment completes, Terraform will output important information:

```bash
terraform output
```

Key outputs:
- `vault_lb_dns_name` - Load balancer DNS name
- `vault_api_url` - Vault API URL
- `kms_key_arn` - KMS key for auto-unseal
- `vpc_id` - VPC ID
- `next_steps` - Post-deployment instructions

### 5. Create DNS Record

Create a DNS record pointing to the load balancer:

**If using Route 53:**
```bash
# Get the load balancer DNS name and zone ID from outputs
LB_DNS=$(terraform output -raw vault_lb_dns_name)
LB_ZONE=$(terraform output -raw vault_lb_zone_id)

# Create Route53 ALIAS record (replace YOUR_ZONE_ID with your Route53 zone ID)
aws route53 change-resource-record-sets \
  --hosted-zone-id YOUR_ZONE_ID \
  --change-batch '{
    "Changes": [{
      "Action": "CREATE",
      "ResourceRecordSet": {
        "Name": "vault.infragoose.com",
        "Type": "A",
        "AliasTarget": {
          "HostedZoneId": "'$LB_ZONE'",
          "DNSName": "'$LB_DNS'",
          "EvaluateTargetHealth": true
        }
      }
    }]
  }'
```

**If using other DNS providers:**
- Create a CNAME record
- Name: `vault.infragoose.com`
- Value: Use the `vault_lb_dns_name` output

### 6. Initialize Vault Cluster

Wait for DNS to propagate (check with `dig vault.infragoose.com`), then initialize Vault:

```bash
export VAULT_ADDR="https://vault.infragoose.com:8200"
vault operator init
```

**CRITICAL**: Save the unseal keys and root token securely! You won't be able to recover them later.

Example output:
```
Unseal Key 1: ...
Unseal Key 2: ...
Unseal Key 3: ...
Unseal Key 4: ...
Unseal Key 5: ...

Initial Root Token: ...
```

### 7. Verify Cluster Status

The cluster should auto-unseal using AWS KMS:

```bash
vault status
```

Expected output:
```
Sealed          false
Total Shares    5
Threshold       3
...
```

### 8. Access Vault UI

Navigate to: `https://vault.infragoose.com:8200/ui`

Login with the root token from step 6.

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

If you want automated Raft snapshots to S3:

1. Create an S3 bucket:
```bash
aws s3 mb s3://vault-snapshots-infragoose --region us-east-1
```

2. Add the bucket ARN to your HCP Terraform workspace:
```
vault_snapshots_bucket_arn = "arn:aws:s3:::vault-snapshots-infragoose"
```

3. Run `terraform apply` again

4. Configure snapshot automation in Vault:
```bash
vault write sys/storage/raft/snapshot-auto/config \
  interval="1h" \
  retain=24 \
  storage_type="aws-s3" \
  aws_s3_bucket="vault-snapshots-infragoose" \
  aws_s3_region="us-east-1"
```

## Rotating Secrets

### Rotating TLS Certificates

1. Update the `vault_tls_cert`, `vault_tls_key`, and `vault_ca_bundle` variables in HCP Terraform workspace
2. Run `terraform apply`
3. Terraform will update the AWS Secrets Manager secrets
4. The Auto Scaling Group will perform rolling updates to replace instances

### Rotating Vault License

1. Update the `vault_license` variable in HCP Terraform workspace
2. Run `terraform apply`
3. New license will be deployed with instance refresh

## Cost Optimization

This deployment includes several cost optimizations:

1. **VPC Endpoints**: Reduce NAT Gateway data transfer costs for AWS service API calls
2. **NAT Gateway per AZ**: High availability while minimizing costs
3. **GP3 EBS volumes**: Better performance-to-cost ratio than GP2
4. **Right-sized instances**: m7i.large provides good performance for most workloads

### Estimated Monthly Costs (us-east-1)

- **EC2 Instances**: 6 × m7i.large × $0.1008/hr = ~$436/month
- **EBS Volumes**: 6 × 180 GB = ~$108/month
- **Application Load Balancer**: ~$23/month
- **NAT Gateways**: 3 × $32.40 = ~$97/month
- **Secrets Manager**: 4 secrets × $0.40 = ~$2/month
- **Data Transfer**: Variable based on usage
- **VPC Endpoints**: ~$22/month (3 interface endpoints)

**Total**: ~$688/month (excluding data transfer)

## Scaling

### Vertical Scaling (Larger Instances)

Update the instance type in HCP Terraform workspace:
```
vm_instance_type = "m7i.xlarge"  # 4 vCPU, 16 GB RAM
```

Run `terraform apply`. Nodes will be replaced one at a time.

### Horizontal Scaling (More Nodes)

Update the node count (must be odd for Raft):
```
asg_node_count = 9
```

Run `terraform apply`.

## Security Best Practices

### Variable Security

- ✅ All sensitive variables (license, certs, keys) are marked as sensitive in Terraform
- ✅ HCP Terraform encrypts sensitive variables at rest
- ✅ Sensitive values never appear in logs or outputs
- ✅ AWS Secrets Manager provides additional encryption layer

### Operational Security

- All secrets are stored in AWS Secrets Manager (not in Terraform state)
- TLS encryption is enforced for all communication
- Auto-unseal uses AWS KMS for enhanced security
- All EBS volumes are encrypted
- Vault nodes are in private subnets (not directly internet-accessible)
- Security groups follow principle of least privilege
- KMS key rotation is enabled
- VPC endpoints reduce exposure to internet

## Disaster Recovery

### Manual Snapshot

```bash
vault operator raft snapshot save backup.snap
```

### Restore from Snapshot

```bash
vault operator raft snapshot restore backup.snap
```

### Multi-Region DR

For production deployments, consider:
1. Deploy a secondary cluster in another region
2. Enable Performance Replication (Vault Enterprise feature)
3. Configure automated failover

## Troubleshooting

### Vault nodes not joining cluster

Check security groups:
```bash
aws ec2 describe-security-groups \
  --filters "Name=tag:Name,Values=*vault*" \
  --query 'SecurityGroups[*].[GroupId,GroupName]' \
  --output table
```

Ensure ports 8200 and 8201 are open between Vault nodes.

### Auto-unseal failing

Verify KMS permissions:
```bash
# Get the IAM role ARN
ROLE_ARN=$(terraform output -raw vault_instance_role_arn)

# Check KMS key policy
KMS_KEY_ID=$(terraform output -raw kms_key_arn)
aws kms get-key-policy --key-id $KMS_KEY_ID --policy-name default
```

### TLS certificate errors

Verify the certificate matches the FQDN:
```bash
openssl s_client -connect vault.infragoose.com:8200 -showcerts
```

### DNS not resolving

Check DNS propagation:
```bash
dig vault.infragoose.com
nslookup vault.infragoose.com
```

### Secrets Manager issues

Verify secrets were created:
```bash
aws secretsmanager list-secrets \
  --filters Key=name,Values=vault \
  --query 'SecretList[*].[Name,ARN]' \
  --output table
```

## Maintenance

### Updating Vault Version

1. Update `vault_version` variable in HCP Terraform workspace
2. Run `terraform apply`
3. The Auto Scaling Group will perform rolling updates

### Patching EC2 Instances

The ASG will automatically replace instances based on launch template changes.

## Resources

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

This configuration is provided as-is. The Vault Enterprise software requires a valid license from HashiCorp.
