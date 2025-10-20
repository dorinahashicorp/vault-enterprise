Vault Enterprise demo deployment (AWS)
=====================================

What this does
---------------
- Wires the HashiCorp "vault-enterprise-hvd" validated-design Terraform module to deploy a small Vault Enterprise cluster in AWS.
- Defaults use small instance types and a 3-node raft cluster appropriate for demos and learning.

Prerequisites (actions outside VS Code)
--------------------------------------
1. Terraform Cloud / HCP
   - In the Infragoose organization create a workspace (or use an existing) named `Vault-Deployments` (or update `versions.tf` with the real name).
   - Enable VCS integration in that workspace pointing to: https://github.com/dorinahashicorp/vault-enterprise. Make sure the repository contains this folder as the working directory, or set the working directory in the workspace.
   - Ensure your AWS credentials are available as a variable set attached to the workspace. You mentioned these are already attached.
   - Add the following sensitive variables to the TFC workspace variable set or workspace variables (sensitive):
     - `sm_vault_license_arn` - ARN of the Secrets Manager secret that contains the Vault license file. Alternatively, you can import the license into Secrets Manager and attach it.
     - `sm_vault_tls_cert_arn` - ARN of the TLS cert secret in Secrets Manager
     - `sm_vault_tls_cert_key_arn` - ARN of the TLS cert private key secret in Secrets Manager
     - `sm_vault_tls_ca_bundle` - ARN of the CA chain secret in Secrets Manager
   - Optionally set `vault_fqdn` (FQDN) variable if you want a specific SAN; otherwise populate with a demo value.

2. AWS (actions outside VS Code)
   - Upload the Vault license file into AWS Secrets Manager in the target region and note the secret ARN.
   - Upload TLS certificate, private key, and CA bundle into Secrets Manager and note their ARNs. The HashiCorp module expects these as separate secrets.

3. VCS repository
   - Push these Terraform files to the GitHub repository `dorinahashicorp/vault-enterprise` (or point your workspace to this repo).

How to run
----------
After you attach variable sets and enable VCS integration in Terraform Cloud the workspace will queue a plan from your git commit. Alternatively, to run locally (not recommended when using Terraform Cloud):

  export AWS_PROFILE=...
  terraform init
  terraform plan
  terraform apply

Notes & best practices
----------------------
- The Terraform state will contain sensitive data (certs and keys). Using Terraform Cloud provides an encrypted remote state. Restrict workspace access.
- For production use follow HashiCorp reference architectures closely and use larger instance types, multi-region designs, and robust logging.
