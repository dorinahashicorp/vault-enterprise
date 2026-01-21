# Bastion Host Access Guide

Quick reference for accessing your Vault cluster through the bastion host.

---

## Step 1: Deploy Bastion Host

The bastion host is defined in `bastion.tf`. Deploy it with:

```bash
terraform plan
terraform apply
```

After deployment, note the outputs:
- `bastion_public_ip`: The public IP to connect to
- `bastion_ssm_command`: Command for Session Manager access

---

## Step 2: Connect to Bastion

### Option A: Session Manager (No SSH Key Required)

```bash
# Get the bastion instance ID from Terraform output
aws ssm start-session --target <bastion-instance-id> --region us-east-1
```

### Option B: SSH (If You Have a Key Pair)

```bash
# Replace with your SSH key and bastion IP
ssh -i ~/.ssh/your-key.pem ec2-user@<bastion-public-ip>
```

---

## Step 3: Access Vault from Bastion

Once connected to the bastion, the Vault CLI is already installed and configured.

### Check Vault Status

```bash
vault status
```

Expected output if Vault is uninitialized:
```
Error checking seal status: Get "https://vault.allincruisive.com:8200/v1/sys/seal-status":
dial tcp: lookup vault.allincruisive.com: no such host
```

This is expected if you haven't created the DNS CNAME yet.

### Use Load Balancer Directly

```bash
# Set Vault address to load balancer DNS
export VAULT_ADDR=https://vault-063f254b96197c1b.elb.us-east-1.amazonaws.com:8200
export VAULT_SKIP_VERIFY=1

# Check status
vault status
```

Expected output for uninitialized Vault:
```
Key                Value
---                -----
Seal Type          awskms
Initialized        false
Sealed             true
Total Shares       0
Threshold          0
Unseal Progress    0/0
Unseal Nonce       n/a
Version            n/a
Storage Type       raft
HA Enabled         true
```

---

## Step 4: Initialize Vault

**IMPORTANT: Only do this once! Save the output securely!**

```bash
vault operator init
```

This will output:
- 5 unseal keys (you won't need these - Vault auto-unseals with KMS)
- 1 root token (save this securely!)

Example output:
```
Recovery Key 1: AbCdEfGhIjKlMnOpQrStUvWxYz
Recovery Key 2: 1234567890abcdefghijklmnopqr
...

Initial Root Token: hvs.XXXXXXXXXXXXXXXXXXXX

Success! Vault is initialized
```

**Save the root token immediately!** Store it in a password manager.

---

## Step 5: Verify Vault is Working

```bash
# Check status (should show initialized and unsealed)
vault status

# Login with root token
vault login <root-token>

# List enabled auth methods
vault auth list

# List enabled secrets engines
vault secrets list
```

---

## Step 6: Create DNS CNAME (After Verification)

Once Vault is working via the load balancer:

1. Go to https://dcc.godaddy.com/control/allincruisive.com/dns
2. Click **Add**
3. Select **CNAME** record
4. Fill in:
   - **Name**: `vault`
   - **Value**: `vault-063f254b96197c1b.elb.us-east-1.amazonaws.com`
   - **TTL**: `600 seconds` (10 minutes)
5. Click **Save**

Wait 1-2 minutes for DNS propagation, then test:

```bash
# From bastion
export VAULT_ADDR=https://vault.allincruisive.com:8200
vault status
```

---

## Step 7: Access from Your Local Machine (After DNS)

Once the DNS CNAME is created:

```bash
# From your local machine
export VAULT_ADDR=https://vault.allincruisive.com:8200
export VAULT_SKIP_VERIFY=1

vault status
vault login <root-token>
```

**Note**: `VAULT_SKIP_VERIFY=1` is needed because Let's Encrypt certificates aren't yet in AWS Secrets Manager (that's done during the initial Terraform apply).

---

## Troubleshooting

### "Connection refused" or timeout
- Check bastion security group allows outbound HTTPS (port 8200)
- Verify Vault instances are running in AWS Console
- Check load balancer target group health

### "No such host" error
- DNS CNAME not created yet - use load balancer DNS directly
- DNS not propagated yet - wait 2-3 minutes

### "Certificate validation failed"
- Use `export VAULT_SKIP_VERIFY=1` to bypass certificate validation
- After initial setup, update certificates in AWS Secrets Manager

---

## Removing the Bastion (Optional)

Once Vault is initialized and DNS is configured, you can remove the bastion:

```bash
# Comment out or delete bastion.tf
# Then apply
terraform apply
```

You can always re-create it later if needed for maintenance.

---

## Summary

1. `terraform apply` - Deploy bastion
2. `aws ssm start-session` - Connect to bastion
3. `export VAULT_ADDR=https://<load-balancer-dns>:8200` - Set Vault address
4. `vault operator init` - Initialize Vault (save root token!)
5. Create DNS CNAME in GoDaddy
6. Test from local machine

**Total time: ~5 minutes**
