# Terraform Configuration Dependency Map

This document visualizes all resource dependencies in the Vault Enterprise HVD Terraform configuration.

## High-Level Architecture

```
┌─────────────────────────────────────────────────────────────────┐
│  PHASE 1: Prerequisites (prerequisites.tf)                      │
│  Status: Must be applied FIRST                                  │
├─────────────────────────────────────────────────────────────────┤
│                                                                 │
│  aws_vpc.main                                                  │
│  ├─ aws_internet_gateway.main                                 │
│  ├─ aws_subnet.public[0,1,2]                                  │
│  ├─ aws_subnet.private[0,1,2]                                 │
│  ├─ aws_eip.nat[0,1,2]                                        │
│  ├─ aws_nat_gateway.main[0,1,2]                               │
│  ├─ aws_route_table.public                                    │
│  ├─ aws_route_table.private[0,1,2]                            │
│  ├─ aws_kms_key.vault                                         │
│  └─ aws_kms_alias.vault                                       │
│                                                                 │
│  OUTPUTS:                                                       │
│  └─ vpc_id, vault_subnet_ids, lb_subnet_ids, kms_key_arn      │
│                                                                 │
└─────────────────────────────────────────────────────────────────┘
                            ↓
              (Manual Step 1: Create secrets)
         Create 4 AWS Secrets Manager secrets:
         - vault-license (with license content)
         - vault-tls-cert (with cert content)
         - vault-tls-key (with key content)
         - vault-ca-cert (with ca-cert content)
                            ↓
┌─────────────────────────────────────────────────────────────────┐
│  PHASE 2: Vault Module (main.tf)                               │
│  Status: Applied AFTER prerequisites + secrets created         │
├─────────────────────────────────────────────────────────────────┤
│                                                                 │
│  module "vault" (hashicorp/terraform-aws-vault-enterprise-hvd) │
│  ├─ INPUT: var.vpc_id ← prerequisites.vpc_id                  │
│  ├─ INPUT: var.vault_subnet_ids ← prerequisites.vault_subnets  │
│  ├─ INPUT: var.lb_subnet_ids ← prerequisites.lb_subnets        │
│  ├─ INPUT: var.kms_key_id ← prerequisites.kms_key_arn          │
│  ├─ INPUT: var.vault_license_secret_arn ← manual secret ARN    │
│  ├─ INPUT: var.vault_tls_cert_secret_arn ← manual secret ARN   │
│  ├─ INPUT: var.vault_tls_key_secret_arn ← manual secret ARN    │
│  ├─ INPUT: var.vault_ca_cert_secret_arn ← manual secret ARN    │
│  └─ CREATES:                                                    │
│     ├─ aws_launch_template                                      │
│     ├─ aws_autoscaling_group                                    │
│     ├─ aws_lb (network load balancer)                           │
│     ├─ aws_lb_target_group                                      │
│     ├─ aws_security_group (vault)                               │
│     ├─ aws_security_group (lb)                                  │
│     ├─ aws_iam_role (vault)                                     │
│     ├─ aws_iam_instance_profile (vault)                         │
│     └─ (EC2 instances launched via ASG)                         │
│                                                                 │
│  OUTPUTS:                                                       │
│  └─ vault_load_balancer_dns, vault_cli_config                  │
│                                                                 │
└─────────────────────────────────────────────────────────────────┘
```

## Resource Dependency Graph

### Prerequisites Phase (prerequisites.tf)

```
aws_vpc.main
├── EXPLICIT depends_on: none
└── IMPLICIT dependencies: none (it's the root)
    └─ Creates: VPC container for all subnets

aws_internet_gateway.main
├── EXPLICIT depends_on: none
├── IMPLICIT dependencies: aws_vpc.main (vpc_id reference)
└─ Creates: Internet access for public subnets

aws_subnet.public[0,1,2]
├── EXPLICIT depends_on: none
├── IMPLICIT dependencies: aws_vpc.main (vpc_id reference)
└─ Creates: 3 public subnets in 3 AZs

aws_subnet.private[0,1,2]
├── EXPLICIT depends_on: none
├── IMPLICIT dependencies: aws_vpc.main (vpc_id reference)
└─ Creates: 3 private subnets in 3 AZs

aws_eip.nat[0,1,2]
├── EXPLICIT depends_on: aws_internet_gateway.main
│   (Ensures IGW is attached before EIP is allocated)
├── IMPLICIT dependencies: none
└─ Creates: Elastic IPs for NAT Gateway (one per public subnet)

aws_nat_gateway.main[0,1,2]
├── EXPLICIT depends_on: aws_internet_gateway.main
│   (Ensures IGW is attached and available)
├── IMPLICIT dependencies:
│   ├─ aws_eip.nat[*] (allocation_id reference)
│   └─ aws_subnet.public[*] (subnet_id reference)
└─ Creates: NAT Gateway (one per public subnet) for private subnet egress

aws_route_table.public
├── EXPLICIT depends_on: none
├── IMPLICIT dependencies: aws_vpc.main (vpc_id reference)
└─ Creates: Route table for public subnets
    └─ Contains route: 0.0.0.0/0 → aws_internet_gateway.main

aws_route_table_association.public[0,1,2]
├── EXPLICIT depends_on: none
├── IMPLICIT dependencies:
│   ├─ aws_subnet.public[*] (subnet_id reference)
│   └─ aws_route_table.public (route_table_id reference)
└─ Creates: Association between public subnets and IGW route table

aws_route_table.private[0,1,2]
├── EXPLICIT depends_on: none
├── IMPLICIT dependencies:
│   ├─ aws_vpc.main (vpc_id reference)
│   ├─ aws_nat_gateway.main[*] (nat_gateway_id reference)
│       └─ NOTE: This is the KEY dependency ensuring NAT GW exists before private routing
└─ Creates: Route table for private subnets (one per AZ)
    └─ Contains route: 0.0.0.0/0 → aws_nat_gateway.main[N]

aws_route_table_association.private[0,1,2]
├── EXPLICIT depends_on: none
├── IMPLICIT dependencies:
│   ├─ aws_subnet.private[*] (subnet_id reference)
│   └─ aws_route_table.private[*] (route_table_id reference)
└─ Creates: Association between private subnets and NAT route table

aws_kms_key.vault
├── EXPLICIT depends_on: none
├── IMPLICIT dependencies: none
└─ Creates: KMS key for Vault auto-unseal

aws_kms_alias.vault
├── EXPLICIT depends_on: none
├── IMPLICIT dependencies: aws_kms_key.vault (target_key_id reference)
└─ Creates: Alias for KMS key (easier to reference)

aws_secretsmanager_secret.vault_license
aws_secretsmanager_secret.vault_tls_cert
aws_secretsmanager_secret.vault_tls_key
aws_secretsmanager_secret.vault_ca_cert
├── EXPLICIT depends_on: none
├── IMPLICIT dependencies: none
└─ Creates: 4 empty secrets in Secrets Manager
    └─ NOTE: User will manually populate these

aws_secretsmanager_secret_version.vault_*[4x]
├── EXPLICIT depends_on: none
├── IMPLICIT dependencies: aws_secretsmanager_secret.vault_* (secret_id reference)
└─ Creates: Placeholder versions in each secret
    └─ NOTE: These will be replaced when user populates secrets
```

### Vault Module Phase (main.tf)

```
module "vault" (from hashicorp/terraform-aws-vault-enterprise-hvd/aws)
├── EXPLICIT depends_on: none
│   (The module doesn't need explicit depends_on because all dependencies
│    are implicit through variable references)
│
└── IMPLICIT dependencies (through variable references):
    ├─ aws_vpc.main
    │  └─ REFERENCE: var.vpc_id (from prerequisites output)
    │
    ├─ aws_subnet.private[*]
    │  └─ REFERENCE: var.vault_subnet_ids (from prerequisites output)
    │
    ├─ aws_subnet.public[*]
    │  └─ REFERENCE: var.lb_subnet_ids (from prerequisites output)
    │     └─ IMPLICIT: depends on aws_nat_gateway.main (through route tables)
    │
    ├─ aws_kms_key.vault
    │  └─ REFERENCE: var.kms_key_id (from prerequisites output)
    │
    ├─ aws_secretsmanager_secret.vault_license
    │  └─ REFERENCE: var.vault_license_secret_arn (from prerequisites output)
    │
    ├─ aws_secretsmanager_secret.vault_tls_cert
    │  └─ REFERENCE: var.vault_tls_cert_secret_arn (from prerequisites output)
    │
    ├─ aws_secretsmanager_secret.vault_tls_key
    │  └─ REFERENCE: var.vault_tls_key_secret_arn (from prerequisites output)
    │
    └─ aws_secretsmanager_secret.vault_ca_cert
       └─ REFERENCE: var.vault_ca_cert_secret_arn (from prerequisites output)
```

## Critical Dependency Path

The most important dependency chain:

```
1. Create 4 Secrets Manager secrets (manual - MUST be done first)
   ├─ vault-license with Vault Enterprise license content
   ├─ vault-tls-cert with TLS certificate content
   ├─ vault-tls-key with TLS private key content
   └─ vault-ca-cert with CA certificate content
   ↓ (record the ARNs of each secret)

2. aws_vpc.main (terraform creates)
   ↓ (depends on)

3. aws_nat_gateway.main[*] (terraform creates)
   ↓ (depends on)

4. aws_route_table.private[*] (terraform creates, references NAT GW)
   ↓ (depends on)

5. aws_subnet.private[*] (terraform creates, has proper routing to internet)
   ↓ (referenced by)

6. module.vault (terraform creates)
   ├─ Retrieves certificates from Secrets Manager secrets (created in step 1)
   ├─ Uses KMS key for auto-unseal
   ├─ Deploys in private subnets with NAT access
   └─ Configures load balancer for high availability
```

If this chain is broken, the deployment will fail:
- Skip manual secret creation → Vault instances will fail to start (missing certs/license)
- Skip prerequisites → Variables undefined → Vault module fails to plan
- Skip NAT Gateway → Private instances can't reach internet → Package downloads fail

## Dependency Management Strategy

### Implicit Dependencies (Preferred)

Most dependencies are implicit through Terraform resource references:

```hcl
resource "aws_nat_gateway" "main" {
  subnet_id = aws_subnet.public[count.index].id  # ← Implicit dependency
  # Terraform automatically knows:
  # - This resource depends on aws_subnet.public
  # - AWS subnet must exist before NAT GW can be created
}
```

**Benefits**:
- Terraform handles ordering automatically
- Code is cleaner and more readable
- No risk of cyclic dependencies

### Explicit Dependencies (Used Sparingly)

Only used when implicit dependencies aren't sufficient:

```hcl
resource "aws_nat_gateway" "main" {
  depends_on = [aws_internet_gateway.main]  # ← Explicit dependency
  # AWS technically doesn't require this, but it's good practice
  # to ensure IGW is attached before NAT GW is created
}
```

**When to use**:
- Non-obvious ordering requirements
- Documentation/clarity
- AWS API limitations

## Verifying Dependencies

To verify Terraform understands dependencies correctly:

```bash
# Show the dependency graph
terraform graph | dot -Tpng > graph.png

# Show what would be created in order
terraform plan

# Specific resource dependencies
terraform graph | grep 'aws_nat_gateway' | head -10
```

## Phase Separation Benefits

By separating prerequisites and vault module:

1. **Isolation**: Prerequisites can be updated independently
2. **Reusability**: One VPC can support multiple Vault deployments
3. **Safety**: Module is never modified; only inputs change
4. **Clarity**: Dependencies are explicit through variable passing
5. **Debugging**: Problems in each phase are easier to isolate

## Manual Dependency (Secret Creation)

One dependency **MUST be handled outside Terraform**: **creating Secrets Manager secrets with actual content**.

```
BEFORE running terraform apply
├─ Use AWS CLI to create 4 secrets
│  ├─ vault-license (populate with license file content)
│  ├─ vault-tls-cert (populate with cert.pem content)
│  ├─ vault-tls-key (populate with key.pem content)
│  └─ vault-ca-cert (populate with ca.pem content)
│
├─ Record the ARN of each secret
│  └─ Format: arn:aws:secretsmanager:REGION:ACCOUNT:secret:NAME-XXXXX
│
└─ Provide ARNs as terraform variables when running apply
   ├─ vault_license_secret_arn
   ├─ vault_tls_cert_secret_arn
   ├─ vault_tls_key_secret_arn
   └─ vault_ca_cert_secret_arn

terraform apply (main.tf)
├─ Creates VPC, subnets, NAT, KMS
└─ Deploys Vault using secrets created above
```

**Why this approach?**

1. **Security**: Certificates and license are never stored in Terraform state
2. **Control**: You retain direct control of sensitive material
3. **Auditability**: Can track who created/modified secrets via CloudTrail
4. **Flexibility**: Secrets can exist in different AWS accounts if needed

**Example AWS CLI commands**:

```bash
# Create secrets before running terraform
aws secretsmanager create-secret \
  --name vault-license \
  --secret-string file://vault.hclic

aws secretsmanager create-secret \
  --name vault-tls-cert \
  --secret-string file://cert.pem

aws secretsmanager create-secret \
  --name vault-tls-key \
  --secret-string file://key.pem

aws secretsmanager create-secret \
  --name vault-ca-cert \
  --secret-string file://ca.pem

# Get the ARN of each secret
aws secretsmanager describe-secret --secret-id vault-license --query 'ARN'
# Output: arn:aws:secretsmanager:us-east-1:123456789012:secret:vault-license-AbCdE
```
