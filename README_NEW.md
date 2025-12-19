# Vault Enterprise on AWS - HVD Architecture

This Terraform configuration deploys Vault Enterprise on AWS EC2 using the HashiCorp Validated Design (HVD) architecture via the official HashiCorp Terraform module.

## Architecture

- **3-node HA cluster** using Raft integrated storage
- **Auto-unseal** with AWS KMS
- **Network Load Balancer** for client access
- **Private subnets** for Vault nodes
- **Secrets Manager** for TLS certificates and Vault license
- **HCP Vault integration** for dynamic secrets retrieval

## Prerequisites

### AWS Setup
1. **VPC with 6 subnets** (3 private, 3 public - one per AZ)
2. **KMS key** for auto-unseal
3. **Secrets Manager** with:
   - TLS certificate
   - TLS certificate key
   - CA certificate
   - Vault Enterprise license
   - HCP Vault authentication token

### HCP Vault Setup
1. HCP Vault Dedicated cluster
2. KV v2 mount with certificate secrets
3. JWT auth method for Terraform authentication

### Terraform Cloud
1. HCP Terraform workspace configured
2. OIDC-based AWS authentication (workload identity)

## Configuration

1. **Copy variables file:**
   ```bash
   cp terraform.tfvars.example terraform.tfvars
   ```

2. **Edit `terraform.tfvars` with your values:**
   - VPC and subnet IDs
   - KMS key ARN
   - Secrets Manager ARNs
   - HCP Vault credentials
   - Vault FQDN

3. **Initialize Terraform:**
   ```bash
   terraform init
   ```

4. **Plan deployment:**
   ```bash
   terraform plan
   ```

5. **Apply configuration:**
   ```bash
   terraform apply
   ```

## Vault Access

After deployment, get the load balancer address:

```bash
terraform output vault_load_balancer_dns
```

### Initialize Vault

The cluster will deploy in uninitialized state. Initialize via the LB:

```bash
export VAULT_ADDR="https://$(terraform output -raw vault_load_balancer_dns):8200"
export VAULT_SKIP_VERIFY=true

vault operator init
```

## Outputs

- `vault_load_balancer_dns` - DNS name for Vault access
- `vault_address` - Full HTTPS address
- `vault_cli_env` - Environment variables for CLI
- `vault_nodes` - Deployment details

## Module Reference

This uses the official HashiCorp module:
https://registry.terraform.io/modules/hashicorp/terraform-aws-vault-enterprise-hvd/aws

See module documentation for additional configuration options.

## Next Steps

1. Initialize the Vault cluster
2. Configure authentication methods (OIDC, AppRole, etc.)
3. Set up audit logging
4. Configure auto-snapshots (optional)
5. Implement backup procedures

## Troubleshooting

Check EC2 instance user data logs:
```bash
aws ec2 get-console-output --instance-id <instance-id>
```

Check Vault status via LB:
```bash
curl -k https://<lb-dns>:8200/v1/sys/health
```

SSH to instance (if SSH access configured):
```bash
aws ssm start-session --target <instance-id>
```
