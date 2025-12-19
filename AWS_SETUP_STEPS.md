# AWS Setup for Vault Enterprise HVD

This document outlines the AWS prerequisites that must be in place **before** running `terraform apply`. These steps follow the official [Vault Enterprise HVD module prerequisites](https://github.com/hashicorp/terraform-aws-vault-enterprise-hvd#prerequisites).

## Prerequisites Checklist

- [ ] VPC created with 3 private subnets (one per AZ)
- [ ] VPC created with 3 public subnets (one per AZ) for load balancer
- [ ] NAT Gateways in public subnets for private subnet internet access
- [ ] KMS key created for auto-unseal
- [ ] TLS certificates obtained (signed cert, private key, CA cert)
- [ ] Vault Enterprise license obtained
- [ ] AWS Secrets Manager secrets created
- [ ] IAM permissions sufficient for Terraform to deploy

## Step-by-Step Setup

### 1. VPC and Networking

Your VPC must have:
- **3 private subnets** for Vault EC2 instances (one per AZ)
- **3 public subnets** for Network Load Balancer (one per AZ)
- **NAT Gateways** in public subnets so private instances can download packages

**Note:** If you don't have this infrastructure, create it in AWS Console or via separate Terraform before running this module.

### 2. KMS Key for Auto-Unseal

Create a KMS key in AWS KMS:

```bash
# Create key
aws kms create-key \
  --description "Vault auto-unseal key" \
  --region us-east-1 \
  --output json

# Note the KeyId from the output, then get its ARN
aws kms describe-key \
  --key-id <KEY_ID> \
  --region us-east-1 \
  --query 'Key.Arn' \
  --output text

# Example output: arn:aws:kms:us-east-1:123456789012:key/12345678-1234-1234-1234-123456789012
```

Save this ARN—you'll need it for `terraform.tfvars`.

### 3. TLS Certificates and License

You need:
1. **Server certificate** (signed by a CA you trust)
2. **Private key** for the certificate
3. **CA certificate** (certificate authority that signed your server cert)
4. **Vault Enterprise license** (from HashiCorp)

If you have these in HCP Vault Dedicated, you can retrieve them:

```bash
# From your HCP Vault instance:
vault kv get -field=server_cert kv/vault > cert.pem
vault kv get -field=server_key kv/vault > key.pem
vault kv get -field=ca_cert kv/vault > ca.pem
vault kv get -field=license kv/vault > license.hclic
```

### 4. Create AWS Secrets Manager Secrets

Using the certificate and license files from Step 3, create secrets in AWS Secrets Manager:

```bash
# Create license secret
aws secretsmanager create-secret \
  --name vault-license \
  --secret-string "$(cat license.hclic)" \
  --region us-east-1

# Create TLS certificate secret
aws secretsmanager create-secret \
  --name vault-tls-cert \
  --secret-string "$(cat cert.pem)" \
  --region us-east-1

# Create TLS private key secret
aws secretsmanager create-secret \
  --name vault-tls-key \
  --secret-string "$(cat key.pem)" \
  --region us-east-1

# Create CA certificate secret
aws secretsmanager create-secret \
  --name vault-ca-cert \
  --secret-string "$(cat ca.pem)" \
  --region us-east-1
```

**Important:** These secret values must be PEM-formatted text. If your secret is binary, the module won't work.

### 5. Get Secret ARNs

Retrieve the ARNs of the secrets you just created:

```bash
# Get all secret ARNs
aws secretsmanager describe-secret --secret-id vault-license --query ARN --output text
aws secretsmanager describe-secret --secret-id vault-tls-cert --query ARN --output text
aws secretsmanager describe-secret --secret-id vault-tls-key --query ARN --output text
aws secretsmanager describe-secret --secret-id vault-ca-cert --query ARN --output text
```

Save these ARNs—you'll enter them in `terraform.tfvars`.

### 6. Verify IAM Permissions

Ensure your Terraform AWS credentials have permissions to:

**For EC2 instances to retrieve secrets:**
- `secretsmanager:GetSecretValue`
- `kms:Decrypt`
- `kms:DescribeKey`

**For Terraform to deploy:**
- `ec2:*` (for ASG, launch templates, security groups)
- `elasticloadbalancing:*` (for load balancer)
- `iam:*` (for instance profiles and roles)
- `kms:DescribeKey` (to verify KMS key)

## Terraform Configuration

Once all AWS prerequisites are in place:

1. Copy `terraform.tfvars.example` to `terraform.tfvars`
2. Fill in the values (VPC IDs, subnet IDs, KMS ARN, secret ARNs)
3. Run `terraform init`
4. Run `terraform plan`
5. Run `terraform apply`

## Troubleshooting

### EC2 instances failing to retrieve secrets
- Verify secrets exist in Secrets Manager
- Verify secret values are PEM-formatted text (not binary)
- Verify IAM role has `secretsmanager:GetSecretValue` permission for those specific secrets
- Check EC2 instance system logs: `aws ec2 get-console-output --instance-id <instance-id>`

### Vault not starting
- Check logs: `sudo journalctl -u vault -n 50`
- Verify KMS key ARN is correct and EC2 role can access it
- Verify certificate and key are valid PEM format

### Load balancer not healthy
- Wait a few minutes—Vault needs time to initialize and unseal
- Check target group health: `aws elbv2 describe-target-health --target-group-arn <arn>`
- Check Vault logs for startup errors
