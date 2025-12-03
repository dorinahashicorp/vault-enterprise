# Vault Enterprise Deployment on AWS via HCP Terraform

A learning project to deploy HashiCorp Vault Enterprise in AWS following HashiCorp best practices, orchestrated through HCP Terraform and integrated with HCP Vault Dedicated for secrets management.

## Architecture Overview

This configuration deploys a production-ready Vault Enterprise cluster on AWS with:

- **3-node HA cluster** using Raft storage backend
- **Auto-unseal** via AWS KMS
- **Load-balanced access** across availability zones
- **Encrypted TLS** communication with certificates stored in HCP Vault
- **Secrets orchestration** through HCP Vault Dedicated JWT authentication with workload identity tokens

### Component Diagram

```
┌─────────────────────────────────────────────────────────────┐
│ HCP Terraform (Infragoose/vault-enterprise)                  │
│  ├─ Workload Identity (JWT Provider)                         │
│  ├─ VCS: dorinahashicorp/vault-enterprise (GitHub)          │
│  └─ Environment Variables (Variable Set):                    │
│     ├─ TFC_VAULT_PROVIDER_AUTH = true                       │
│     ├─ TFC_VAULT_ADDR = Vault cluster address               │
│     ├─ TFC_VAULT_NAMESPACE = admin                          │
│     ├─ TFC_VAULT_RUN_ROLE = tfc-role                        │
│     └─ AWS_ACCESS_KEY_ID, AWS_SECRET_ACCESS_KEY             │
└─────────────────────────────────────────────────────────────┘
                          │
         ┌────────────────┴────────────────┐
         ▼                                  ▼
┌──────────────────────────┐    ┌──────────────────────────┐
│ HCP Vault Dedicated      │    │ AWS (us-east-1)          │
│ (admin namespace)        │    │                          │
│                          │    │ ├─ EC2 (3x t3.medium)   │
│ JWT Auth: tfc-role      │    │ ├─ NLB                  │
│  └─ Workload Identity   │    │ ├─ KMS (auto-unseal)    │
│     Audience            │    │ └─ Security Groups      │
│                          │    │                          │
│ KV Mount: kv/           │    │ VPC: 10.50.0.0/16       │
│  └─ vault/              │    │                          │
│     ├─ ca_cert          │    └──────────────────────────┘
│     ├─ license          │
│     ├─ server_cert      │
│     └─ server_key       │
└──────────────────────────┘
```

## Authentication Flow

**HCP Terraform → HCP Vault (JWT Workload Identity)**

1. **Token Generation**: HCP Terraform generates a short-lived JWT token containing:
   - `aud` (audience): `vault.workload.identity`
   - `sub` (subject): `organization:Infragoose:project:*:workspace:vault-enterprise:run_phase:*`
   - Workspace identity and run context
   
2. **Token Validation**: Vault validates the JWT using HCP Terraform's OIDC discovery endpoint:
   - Verifies signature using HCP Terraform's public keys
   - Confirms issuer is `https://app.terraform.io`
   - Matches bound_claims against workspace identity
   
3. **Token Exchange**: Vault exchanges the JWT for a temporary access token with:
   - `tfc-policy` attached (read-only access to secrets)
   - 20-minute TTL (renewable)
   
4. **Secret Retrieval**: Temporary token is used to fetch secrets from `kv/vault`

5. **Token Lifecycle**: HCP Terraform:
   - Manages the token file throughout the run
   - Renews the token if runs exceed 20 minutes
   - Revokes the token at run completion

## Secrets Management Flow (Updated)

1. **Terraform Run Start**: HCP Terraform generates workload identity JWT token
2. **JWT Auth**: Authenticates to HCP Vault using:
   - Signed JWT token (auto-provided by HCP Terraform)
   - JWT auth method at `auth/jwt/` path
   - Role binding to `tfc-role` with workspace identity claims
3. **Token Exchange**: JWT is validated and exchanged for temporary access token with:
   - `tfc-policy` permissions
   - 20-minute TTL with renewal capability
4. **Secret Retrieval**: Fetches secrets from `kv/vault` in the `admin` namespace:
   - `ca_cert` → Passed to AWS as TLS CA bundle
   - `license` → Passed to AWS for Vault licensing
   - `server_cert` → Passed to AWS for TLS server certificate
   - `server_key` → Passed to AWS for TLS server private key
5. **Cluster Provisioning**: AWS resources are created with the secrets
6. **Token Cleanup**: Token is automatically revoked when the Terraform run completes

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

### 2. HCP Vault JWT Authentication Configuration

The JWT authentication method has been pre-configured in HCP Vault. The configuration establishes trust between HCP Terraform and HCP Vault:

**JWT Auth Backend** (`auth/jwt/`):
- **OIDC Discovery URL**: `https://app.terraform.io`
- **Bound Issuer**: `https://app.terraform.io`
- Validates JWTs signed by HCP Terraform's workload identity provider

**JWT Role** (`auth/jwt/role/tfc-role`):
- **Bound Audience**: `vault.workload.identity`
- **Bound Claims**: Matches workspace identity pattern:
  ```
  organization:Infragoose:project:*:workspace:vault-enterprise:run_phase:*
  ```
- **Attached Policy**: `tfc-policy` (read-only access to Vault secrets)
- **Token TTL**: 20 minutes (renewable for runs exceeding 20 minutes)

**Policy** (`tfc-policy`):
```hcl
# Allow tokens to query themselves
path "auth/token/lookup-self" {
  capabilities = ["read"]
}

# Allow tokens to renew themselves
path "auth/token/renew-self" {
  capabilities = ["update"]
}

# Allow tokens to revoke themselves
path "auth/token/revoke-self" {
  capabilities = ["update"]
}

# Allow reading KV v2 secrets
path "kv/data/vault" {
  capabilities = ["read"]
}

# Allow listing KV mount
path "kv/metadata/*" {
  capabilities = ["list"]
}
```

#### Why JWT Instead of AppRole?

**AppRole Limitations in HCP Vault Dedicated**:
- Difficult to manage secret_id rotation
- Secret IDs are credentials requiring secure storage
- Namespace-scoped policy evaluation in child namespaces can be problematic

**JWT Workload Identity Benefits**:
- ✅ **No Secrets to Manage**: Tokens are generated by HCP Terraform automatically
- ✅ **Passwordless**: Zero-trust architecture using cryptographic signatures
- ✅ **Automatic Lifecycle**: HCP Terraform manages token generation, renewal, and revocation
- ✅ **Audit Trail**: Each run has a distinct token with workspace identity context
- ✅ **Short-Lived**: 20-minute TTL minimizes exposure window
- ✅ **Namespace-Safe**: Works reliably across all namespace configurations

### 3. HCP Terraform Workspace Setup
The `vault-enterprise` workspace in the `Infragoose` organization requires:

**Required Terraform Variable**:
- `tfc_vault_dynamic_credentials` (object): This is automatically provided by HCP Terraform when the environment variables below are set. Do NOT set this manually.

**Required Environment Variables** (set in workspace variable set):
- `TFC_VAULT_PROVIDER_AUTH` (string): **Must be `true`** - enables dynamic credential provider authentication
- `TFC_VAULT_ADDR` (string): Your HCP Vault Dedicated cluster URL
  - Example: `https://dorina-demo-cluster-public-vault-xxxxx.z1.hashicorp.cloud:8200`
- `TFC_VAULT_NAMESPACE` (string): Vault namespace (use `admin`)
- `TFC_VAULT_RUN_ROLE` (string): Vault JWT role name (use `tfc-role`)

**AWS Credentials Variable Set**:
- `AWS_ACCESS_KEY_ID` (string, sensitive): AWS IAM access key
- `AWS_SECRET_ACCESS_KEY` (string, sensitive): AWS IAM secret key

#### Setting Up Environment Variables in HCP Terraform

1. In the `vault-enterprise` workspace settings, navigate to **Variables**
2. Click **Add variable set** or attach an existing one
3. Create/update a variable set with the required environment variables:

```
TFC_VAULT_PROVIDER_AUTH = true
TFC_VAULT_ADDR = https://dorina-demo-cluster-public-vault-xxxxx.z1.hashicorp.cloud:8200
TFC_VAULT_NAMESPACE = admin
TFC_VAULT_RUN_ROLE = tfc-role
AWS_ACCESS_KEY_ID = (your AWS key)
AWS_SECRET_ACCESS_KEY = (your AWS secret)
```

4. Mark sensitive variables as **sensitive** (toggles next to the values)
5. Attach the variable set to the workspace

**How It Works**:
- When a Terraform run starts, HCP Terraform automatically generates a JWT token containing:
  - Organization: `Infragoose`
  - Workspace: `vault-enterprise`
  - Run phase information
- The JWT is written to a temporary file with path provided via `TFC_VAULT_TOKEN` environment variable
- Terraform provider reads this file and authenticates to Vault without needing credentials in code
- Vault validates the JWT against HCP Terraform's OIDC endpoint and issues a temporary access token
- The temporary token is used to read secrets and then automatically revoked

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

# Check JWT auth method configuration
vault read auth/jwt/config

# Verify JWT role is configured
vault read auth/jwt/role/tfc-role
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
- All secrets sourced from HCP Vault via JWT workload identity
- Sensitive variables marked in TFC
- Passwordless authentication (no static secrets to manage)

✅ **Authentication (JWT Workload Identity)**
- Zero-trust architecture using cryptographic signatures
- Automatic token generation and lifecycle management by HCP Terraform
- Short-lived tokens (20-minute TTL) minimize exposure
- Workspace identity binding ensures run context isolation
- HCP Terraform handles token renewal and revocation

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
- JWT validation prevents unauthorized access

✅ **Infrastructure as Code**
- Terraform modules from HashiCorp Registry
- Version constraints for reproducibility
- Clean variable design with sensible defaults
- Documented outputs for operational use
- Dynamic provider credentials eliminate static secret management

## Troubleshooting

### "Module not installed" Error
```bash
terraform init
```

### JWT Authentication Failures
- Verify `TFC_VAULT_PROVIDER_AUTH` is set to `true` in the workspace
- Confirm `TFC_VAULT_ADDR` matches your Vault cluster address
- Check `TFC_VAULT_NAMESPACE` is set to `admin`
- Verify `TFC_VAULT_RUN_ROLE` is set to `tfc-role`
- Ensure HCP Terraform has outbound HTTPS access to:
  - Your Vault cluster
  - `https://app.terraform.io` (for OIDC discovery)

### JWT Token File Not Found
- This means HCP Terraform did not generate the JWT token
- Verify `TFC_VAULT_PROVIDER_AUTH=true` is set
- Check HCP Terraform logs in the run output
- Confirm all `TFC_VAULT_*` variables are configured

### Vault Nodes Not Becoming Healthy
- Check EC2 instance security groups (allow port 8200, 8201)
- Verify KMS key permissions for EC2 role
- Check VPC network ACLs allow traffic between subnets

### JWT Token File Not Found
- This means HCP Terraform did not generate the JWT token
- Verify `TFC_VAULT_PROVIDER_AUTH=true` is set in workspace variables
- Check HCP Terraform logs in the run output for credential errors
- Confirm all `TFC_VAULT_*` environment variables are configured

### JWT Authentication Failures in Terraform Run
- Verify `TFC_VAULT_ADDR` is reachable from HCP Terraform
- Confirm `TFC_VAULT_NAMESPACE` is set to `admin`
- Check `TFC_VAULT_RUN_ROLE` is set to `tfc-role`
- Verify workspace identity pattern matches:
  - `organization:Infragoose:project:*:workspace:vault-enterprise:run_phase:*`
- Review Vault audit logs: `vault audit list -namespace=admin`
- Test JWT role locally: `vault write auth/jwt/role/tfc-role -namespace=admin`

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
- [Vault JWT Authentication](https://www.vaultproject.io/docs/auth/jwt)
- [HCP Terraform Dynamic Credentials with Vault](https://developer.hashicorp.com/terraform/cloud-docs/dynamic-provider-credentials/vault-configuration)
- [HCP Terraform Workload Identity](https://developer.hashicorp.com/terraform/cloud-docs/workloads/identity)
- [HCP Terraform Documentation](https://developer.hashicorp.com/terraform/cloud-docs)
- [HCP Vault Dedicated Documentation](https://cloud.hashicorp.com/docs/vault/dedicated)

## Learning Goals

This project demonstrates:
- ✅ Vault Enterprise deployment architecture
- ✅ Multi-cloud secrets orchestration (Vault + AWS)
- ✅ IaC best practices with Terraform
- ✅ JWT workload identity authentication (passwordless)
- ✅ HCP Terraform dynamic provider credentials
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
