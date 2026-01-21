# Certificate Renewal Guide

This guide shows you the **exact steps** to renew your Vault TLS certificate every 60-90 days.

## What Gets Automated vs Manual

- ✅ **Automated**: Updating the 3 certificate variables in HCP Terraform (via GitHub Actions)
- ⚠️  **Manual**: Running certbot locally to renew the certificate (because GoDaddy DNS requires manual TXT record creation)

**Total time required: ~7-8 minutes every 60-90 days**

---

## One-Time Setup (Do This Once)

### Add GitHub Secret for HCP Terraform Token

1. **Get your HCP Terraform API token**:
   - Go to https://app.terraform.io/app/settings/tokens
   - Click "Create an API token"
   - Give it a name: `Certificate Renewal Automation`
   - Copy the token (you won't see it again!)

2. **Add it as a GitHub secret**:
   - Go to https://github.com/dorinahashicorp/vault-enterprise/settings/secrets/actions
   - Click **New repository secret**
   - **Name**: `HCP_TERRAFORM_TOKEN`
   - **Secret**: Paste the token you copied above
   - Click **Add secret**

✅ **Setup complete!** You only need to do this once.

---

## Certificate Renewal Process (Every 60-90 Days)

### Step 1: Renew Certificate Locally with Certbot

Open your terminal and run:

```bash
sudo certbot renew --cert-name vault.allincruisive.com --force-renewal
```

**What happens:**
1. Certbot will contact Let's Encrypt
2. Let's Encrypt will provide a DNS challenge (a random string)
3. Certbot will display something like:

```
Please deploy a DNS TXT record under the name:
_acme-challenge.vault.allincruisive.com

with the following value:
JoXZAbzxQWNSQDp9G_inF8VWODZbHpNf6OmMqVQL-4s

Before continuing, verify the TXT record has been deployed.
Press Enter to Continue
```

4. **DO NOT PRESS ENTER YET!** First, create the DNS record in Step 1a below.

#### Step 1a: Create DNS TXT Record in GoDaddy

1. Open a new browser tab
2. Go to your GoDaddy DNS management: https://dcc.godaddy.com/control/allincruisive.com/dns
3. Click **Add** button
4. Select **TXT** record type
5. Fill in:
   - **Name**: `_acme-challenge.vault` (GoDaddy automatically adds .allincruisive.com)
   - **Value**: Paste the exact value from certbot (e.g., `JoXZAbzxQWNSQDp9G_inF8VWODZbHpNf6OmMqVQL-4s`)
   - **TTL**: `600 seconds`
6. Click **Save**
7. Wait 1-2 minutes for DNS propagation

#### Step 1b: Verify and Complete Renewal

Back in your terminal:

1. Verify the DNS record is live (optional but recommended):
   ```bash
   dig _acme-challenge.vault.allincruisive.com TXT +short
   ```
   You should see your TXT record value in quotes.

2. Press **Enter** in the certbot terminal

3. Certbot will verify the DNS record and issue your new certificate

4. You'll see:
   ```
   Successfully received certificate.
   Certificate is saved at: /etc/letsencrypt/live/vault.allincruisive.com/fullchain.pem
   Key is saved at:         /etc/letsencrypt/live/vault.allincruisive.com/privkey.pem
   ```

✅ **Certificate renewed locally!**

---

### Step 2: Copy Certificate Content

Now read the three certificate files:

```bash
# 1. Full chain certificate
sudo cat /etc/letsencrypt/live/vault.allincruisive.com/fullchain.pem

# 2. Private key
sudo cat /etc/letsencrypt/live/vault.allincruisive.com/privkey.pem

# 3. CA chain
sudo cat /etc/letsencrypt/live/vault.allincruisive.com/chain.pem
```

**Keep this terminal open** - you'll need to copy these values in the next step.

---

### Step 3: Update HCP Terraform Variables via GitHub Actions

1. **Go to GitHub Actions**:
   - Open https://github.com/dorinahashicorp/vault-enterprise/actions

2. **Select the workflow**:
   - In the left sidebar, click **"Renew Vault TLS Certificate"**

3. **Run the workflow**:
   - Click the **"Run workflow"** dropdown button (top right, blue button)
   - You'll see three input boxes

4. **Paste certificate content**:
   - **cert_fullchain**: Copy/paste entire content from `fullchain.pem` (including `-----BEGIN CERTIFICATE-----` and `-----END CERTIFICATE-----`)
   - **cert_privkey**: Copy/paste entire content from `privkey.pem` (including `-----BEGIN PRIVATE KEY-----` and `-----END PRIVATE KEY-----`)
   - **cert_chain**: Copy/paste entire content from `chain.pem` (including `-----BEGIN CERTIFICATE-----` and `-----END CERTIFICATE-----`)

5. **Click "Run workflow"** (green button at bottom)

**What happens:**
- GitHub Actions connects to HCP Terraform API
- Updates all three certificate variables automatically
- Shows success message when done (takes ~30 seconds)

✅ **HCP Terraform variables updated!**

---

### Step 4: Apply Changes in HCP Terraform

1. **Go to your workspace**:
   - Open https://app.terraform.io/app/Infragoose/workspaces/vault-enterprise

2. **Verify variables were updated** (optional):
   - Click **Variables** tab
   - Look for `vault_tls_cert`, `vault_tls_key`, `vault_ca_bundle`
   - Description should say "Updated via GitHub Actions on [today's date]"

3. **Start a new run**:
   - Click **Actions** dropdown (top right)
   - Click **"Start new run"**
   - Click **"Start run"**

4. **Review the plan**:
   - Terraform will show changes to AWS Secrets Manager (the 3 certificate secrets)
   - Should say something like: `3 to change` (vault_tls_cert, vault_tls_key, vault_ca_bundle in Secrets Manager)

5. **Apply the changes**:
   - Click **"Confirm & Apply"**
   - Add a comment like "Certificate renewal - expires [new expiry date]"
   - Click **"Confirm plan"**

6. **Wait for completion**:
   - Apply takes 1-2 minutes
   - Vault instances automatically reload with new certificates
   - **No downtime!** Vault does graceful reload

✅ **Certificate renewal complete!**

---

### Step 5: Verify New Certificate (Optional)

Check that Vault is using the new certificate:

```bash
echo | openssl s_client -servername vault.allincruisive.com \
  -connect vault.allincruisive.com:8200 2>/dev/null \
  | openssl x509 -noout -dates
```

You should see:
```
notBefore=Jan 21 12:54:16 2026 GMT
notAfter=Apr 21 12:54:15 2026 GMT
```

The `notAfter` date should be ~90 days in the future.

---

### Step 6: Clean Up DNS Record (Optional)

You can delete the temporary TXT record from GoDaddy:

1. Go to https://dcc.godaddy.com/control/allincruisive.com/dns
2. Find the TXT record: `_acme-challenge.vault`
3. Click the trash icon to delete it
4. Click **Save**

This record is only needed during renewal, not after.

---

## Quick Reference

### When to Renew

Set a calendar reminder for **60 days from now** to renew the certificate before it expires at 90 days.

To calculate the reminder date:
```bash
date -v+60d  # macOS
date -d "+60 days"  # Linux
```

### Check Certificate Expiry

Check when your current certificate expires:

```bash
echo | openssl s_client -servername vault.allincruisive.com \
  -connect vault.allincruisive.com:8200 2>/dev/null \
  | openssl x509 -noout -dates
```

### Time Breakdown

| Step | Time Required | Automated? |
|------|--------------|------------|
| Step 1: Renew cert locally | 3-5 minutes | ⚠️ Manual (DNS TXT record) |
| Step 2: Copy cert content | 30 seconds | ⚠️ Manual |
| Step 3: Update HCP Terraform | 30 seconds | ✅ Automated (GitHub Actions) |
| Step 4: Apply in HCP Terraform | 2-3 minutes | ⚠️ Manual review + auto apply |
| **Total** | **~7-8 minutes** | **Semi-automated** |

---

## Alternative: Shell Script Method

If you prefer command-line tools over GitHub Actions, use the shell script:

```bash
cd /Users/dorinatimbur/vault-enterprise-1/scripts
export HCP_TERRAFORM_TOKEN="your-token-here"
./renew-vault-cert.sh
```

This script does Steps 2-3 automatically (reads cert files and updates HCP Terraform). You still need to do Step 1 (certbot renewal) manually.

See [scripts/README.md](scripts/README.md) for details.

---

## Troubleshooting

### Certbot Renewal Fails

**Problem**: Certbot can't connect to Let's Encrypt

**Solution**:
- Check internet connection
- Try again - Let's Encrypt sometimes has rate limits
- Check certbot logs: `sudo cat /var/log/letsencrypt/letsencrypt.log`

---

**Problem**: DNS validation fails ("Incorrect validation certificate")

**Solution**:
1. Verify TXT record in GoDaddy is correct
2. Wait 2-3 minutes for DNS propagation
3. Verify with: `dig _acme-challenge.vault.allincruisive.com TXT +short`
4. Make sure you see the exact value certbot provided

---

### GitHub Action Fails

**Problem**: "Error: Could not get workspace ID"

**Solution**:
- Check your `HCP_TERRAFORM_TOKEN` secret is correct
- Verify token has access to the workspace
- Go to https://app.terraform.io/app/settings/tokens and create a new token if needed

---

**Problem**: "Variable not found in workspace"

**Solution**:
- The variables `vault_tls_cert`, `vault_tls_key`, `vault_ca_bundle` must already exist
- They were created when you first deployed Vault
- Check in HCP Terraform → Variables tab

---

**Problem**: GitHub Action says "Failed to update" with HTTP error

**Solution**:
- Check the Actions log for the specific error message
- Verify your token hasn't expired
- Ensure the certificate content is complete (includes BEGIN/END lines)

---

### Vault Doesn't Pick Up New Certificate

**Problem**: After applying, Vault still shows old certificate expiry date

**Solution**:
1. Check AWS Secrets Manager was updated:
   - Go to AWS Console → Secrets Manager
   - Look for secrets named `vault-vault-tls-cert`, `vault-vault-tls-key`, `vault-vault-ca-bundle`
   - Verify "Last modified" shows today's date

2. Check Terraform apply completed successfully:
   - Go to HCP Terraform workspace
   - Click "Runs" tab
   - Verify the latest run shows "Applied"

3. Restart Vault instances (if needed):
   ```bash
   # Connect via Session Manager to a Vault instance
   aws ssm start-session --target i-INSTANCEID --region us-east-1

   # Restart Vault service (it will auto-unseal)
   sudo systemctl restart vault
   ```

---

## Security Notes

- ✅ **HCP Terraform token** is stored as a GitHub secret and never exposed in logs
- ✅ **Certificate content** is masked in GitHub Action logs (marked as secrets)
- ✅ **Certificate files** are already in .gitignore and won't be committed
- ✅ **Only repository admins** can view or edit GitHub secrets
- ⚠️  **Rotate HCP Terraform token** periodically (every 6-12 months)

---

## Need More Details?

- **Shell script documentation**: [scripts/README.md](scripts/README.md)
- **Full automation options**: [scripts/README.md#automated-renewal-with-cron](scripts/README.md)
- **HCP Terraform API docs**: https://developer.hashicorp.com/terraform/cloud-docs/api-docs
