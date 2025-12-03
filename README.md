# Vault Enterprise Deployment on AWS via HCP Terraform

A learning project to deploy HashiCorp Vault Enterprise in AWS following HashiCorp best practices, orchestrated through HCP Terraform and integrated with HCP Vault Dedicated for secrets management.

## Architecture Overview

This configuration deploys a production-ready Vault Enterprise cluster on AWS with:

- **3-node HA cluster** using Raft storage backend
- **Auto-unseal** via AWS KMS
- **Load-balanced access** across availability zones
- **Encrypted TLS** communication with certificates stored in HCP Vault
- **Secrets orchestration** through HCP Vault AppRole authentication

### Component Diagram

```
┌─────────────────────────────────────────────────────────────┐
│ HCP Terraform (Infragoose/vault-enterprise)                  │
│  ├─ VCS: dorinahashicorp/vault-enterprise (GitHub)          │
│  └─ Variable Sets (attached):                                │
│     ├─ HCP Vault Dedicated credentials                      │
│     └─ AWS credentials                                      │
└─────────────────────────────────────────────────────────────┘
                          │
                          ▼
┌─────────────────────────────────────────────────────────────┐
│ HCP Vault Dedicated (admin namespace)                        │
│  └─ KV Mount: kv/vault/                                     │
│     ├─ ca_cert      (CA certificate chain)                  │
│     ├─ license      (Vault Enterprise license)              │
│     ├─ server_cert  (Server TLS certificate)                │
│     └─ server_key   (Server TLS private key)                │
└─────────────────────────────────────────────────────────────┘
                          │
                          ▼ (AppRole auth)
┌─────────────────────────────────────────────────────────────┐
│ AWS (us-east-1)                                              │
│  ├─ VPC: 10.50.0.0/16 (demo VPC, auto-created)             │
│  ├─ EC2 Instances: 3x t3.medium (Raft cluster)             │
│  ├─ Network Load Balancer (public subnets)                  │
│  ├─ KMS Key (auto-unseal)                                   │
│  └─ Security Groups (managed by module)                     │
└─────────────────────────────────────────────────────────────┘
```

## Secrets Management Flow

1. **Terraform Init**: HCP Terraform initializes with the vault provider
2. **AppRole Auth**: Authenticates to HCP Vault using:
   - `vault_approle_role_id` (from TFC variable set)
   - `vault_approle_secret_id` (from TFC variable set)
3. **Secret Retrieval**: Fetches secrets from `kv/vault` in the `admin` namespace:
   - `ca_cert` → Passed to AWS as TLS CA bundle
   - `license` → Passed to AWS for Vault licensing
   - `server_cert` → Passed to AWS for TLS server certificate
   - `server_key` → Passed to AWS for TLS server private key
4. **Cluster Provisioning**: AWS resources are created with the secrets

## Prerequisites

### 1. HCP Vault Dedicated Setup
- **Cluster**: Active HCP Vault Dedicated instance
- **Namespace**: `admin` (default)
- **KV Mount**: `kv` with the following secrets at `kv/vault`:
  ```
  ca_cert      - PEM-encoded CA certificate chain
  license      - Vault Enterprise license file content
  server_cert  - PEM-encoded server certificate
  server_key   - PEM-encoded private key
  ```

### 2. HCP Vault AppRole Configuration
Create an AppRole in HCP Vault with:
- Role ID (static identifier)
- Secret ID (sensitive credential)
- Policy: Read-only access to `kv/vault` secrets

Example policy:
```hcl
path "kv/data/vault" {
  capabilities = ["read"]
}
```

### 3. HCP Terraform Workspace Setup
The `vault-enterprise` workspace in the `Infragoose` organization requires two variable sets:

**Variable Set 1: HCP Vault Integration**
- `vault_addr` (string): Your HCP Vault Dedicated cluster URL
  - Example: `https://dorina-demo-cluster-public-vault-xxxxx.z1.hashicorp.cloud:8200`
- `vault_approle_role_id` (string, sensitive): AppRole role ID
- `vault_approle_secret_id` (string, sensitive): AppRole secret ID
- `vault_kv_mount` (string): KV mount name (default: `kv`)
- `vault_kv_path_prefix` (string): Path prefix (default: `vault`)

**Variable Set 2: AWS Credentials**
- `AWS_ACCESS_KEY_ID` (string, sensitive): AWS IAM access key
- `AWS_SECRET_ACCESS_KEY` (string, sensitive): AWS IAM secret key

### 4. VCS Integration
- Repository: `dorinahashicorp/vault-enterprise`
- Branch: `main`
- Working Directory: `/` (root of repository)
- Webhook: GitHub → Terraform Cloud (auto-created by OAuth connection)

## Configuration Variables

### Required Variables
- `vault_fqdn` - FQDN for the Vault cluster (used in TLS SAN)
  - Example: `vault.example.com`

### Optional Variables
- `aws_region` - AWS region (default: `us-east-1`)
- `resource_name_prefix` - Resource naming prefix (default: `demo-vault`)
- `net_vpc_id` - Existing VPC ID (leave empty to create demo VPC)
- `net_vault_subnet_ids` - Existing subnets for Vault instances (leave empty for demo)
- `net_lb_subnet_ids` - Existing subnets for load balancer (leave empty for demo)
- `vault_seal_awskms_key_arn` - Existing KMS key ARN (leave empty to create demo key)
- `resource_tags` - Map of tags for AWS resources

## How to Deploy

### Step 1: Verify Configuration
In HCP Terraform workspace settings:
1. Confirm VCS integration is enabled
2. Verify both variable sets are attached to the workspace
3. Ensure working directory is set correctly

### Step 2: Queue a Plan
```
git push origin main  # Automatically triggers a plan in HCP Terraform
# OR manually queue in HCP Terraform UI
```

### Step 3: Review the Plan
In HCP Terraform:
1. Review the proposed changes (3 EC2 instances, NLB, KMS key, security groups)
2. Verify all secrets were successfully retrieved from HCP Vault
3. Check resource naming and sizing

### Step 4: Apply
Click "Confirm & Apply" in HCP Terraform UI

### Step 5: Monitor Deployment
- Watch EC2 instances launch in AWS
- Monitor auto-unseal KMS key usage
- Wait for load balancer to become healthy (5-10 minutes)

## Post-Deployment

### Accessing Vault
After deployment, outputs provide:
- `vault_lb_dns_name` - Load balancer DNS (use for VAULT_ADDR)
- `vault_cli_env` - Environment variable suggestions

Example:
```bash
export VAULT_ADDR=https://demo-vault-nlb-xxxxx.elb.us-east-1.amazonaws.com:8200
vault status
```

### Cluster Health Checks
```bash
# Check seal status
vault status

# List cluster members
vault operator raft list-peers

# Verify auto-unseal is active
vault read sys/seal-status

# Test auth method
vault login -method=approle \
  role_id=<role_id> \
  secret_id=<secret_id>
```

### HA Testing
- Kill one Vault node → Cluster continues (2 nodes remain)
- Kill second node → Cluster degrades (1 node, no quorum for writes)
- Recover nodes → Auto-rejoin cluster

## Scaling & Customization

### Adding More Nodes
Edit `main.tf`:
```hcl
asg_node_count = 5  # Change from 3 to desired count
```

### Using Larger Instances
Edit `main.tf`:
```hcl
vm_instance_type = "t3.xlarge"  # Change from t3.medium
```

### Using Existing Infrastructure
Provide variable values:
```hcl
net_vpc_id           = "vpc-xxxxx"
net_vault_subnet_ids = ["subnet-1", "subnet-2", "subnet-3"]
net_lb_subnet_ids    = ["subnet-4", "subnet-5", "subnet-6"]
vault_seal_awskms_key_arn = "arn:aws:kms:..."
```

## Best Practices Applied

✅ **Secrets Management**
- No credentials in code or state
- All secrets sourced from HCP Vault via AppRole
- Sensitive variables marked in TFC

✅ **High Availability**
- 3-node Raft cluster (minimum for HA)
- Multi-AZ deployment
- Network Load Balancer for distribution
- Auto-unseal to handle unsealing automatically

✅ **Security**
- TLS encryption (certificates from Vault)
- KMS encryption for auto-unseal
- Security groups restrict network access
- Sensitive data in encrypted remote state (TFC)

✅ **Infrastructure as Code**
- Terraform modules from HashiCorp Registry
- Version constraints for reproducibility
- Clean variable design with sensible defaults
- Documented outputs for operational use

## Troubleshooting

### "Module not installed" Error
```bash
terraform init
```

### Vault Nodes Not Becoming Healthy
- Check EC2 instance security groups (allow port 8200, 8201)
- Verify KMS key permissions for EC2 role
- Check VPC network ACLs allow traffic between subnets

### AppRole Auth Failures
- Verify role ID and secret ID in TFC variables
- Check Vault AppRole policy allows reading `kv/vault`
- Ensure AppRole endpoint is not restricted by network policies

### TLS Certificate Issues
- Verify `server_cert` and `server_key` are valid PEM format
- Check `ca_cert` contains full CA chain
- Ensure `vault_fqdn` matches certificate SANs

## Destroying Resources

⚠️ **Warning**: This will destroy all Vault Enterprise infrastructure

```bash
# Via HCP Terraform UI:
# 1. Queue destroy run
# 2. Confirm when prompted

# Or via CLI:
terraform destroy
```

Note: Vault state (Raft storage) is stored on EC2 instance volumes. Destroying the infrastructure also destroys the state.

## References

- [Vault Enterprise Documentation](https://www.vaultproject.io/docs/enterprise)
- [HashiCorp Vault Enterprise HVD Module](https://registry.terraform.io/modules/hashicorp/vault-enterprise-hvd/aws)
- [Vault AppRole Authentication](https://www.vaultproject.io/docs/auth/approle)
- [HCP Terraform Documentation](https://developer.hashicorp.com/terraform/cloud-docs)
- [HCP Vault Dedicated Documentation](https://cloud.hashicorp.com/docs/vault/dedicated)

## Learning Goals

This project demonstrates:
- ✅ Vault Enterprise deployment architecture
- ✅ Multi-cloud secrets orchestration (Vault + AWS)
- ✅ IaC best practices with Terraform
- ✅ AppRole authentication patterns
- ✅ HA cluster design with Raft
- ✅ Auto-unseal implementation
- ✅ Integration with HCP Terraform
- ✅ Network isolation and security groups

## Support

For issues:
1. Check this README's Troubleshooting section
2. Review HCP Terraform run logs in the UI
3. Check AWS CloudWatch for instance logs
4. Verify Vault cluster health with `vault status`
