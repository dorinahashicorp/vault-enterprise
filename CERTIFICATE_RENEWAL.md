# Certificate Renewal Guide

This guide shows you how to renew your Vault TLS certificate and automatically update HCP Terraform.

## Setup (One-Time)

### 1. Add GitHub Secret

1. Go to https://github.com/dorinahashicorp/vault-enterprise/settings/secrets/actions
2. Click **New repository secret**
3. Add:
   - **Name**: `HCP_TERRAFORM_TOKEN`
   - **Secret**: Your token from https://app.terraform.io/app/settings/tokens
4. Click **Add secret**

That's it! You're ready to use the automated workflow.

## Renewing Certificates (Every 60-90 Days)

### Step 1: Renew Certificate Locally

Run certbot to renew your certificate:

```bash
sudo certbot renew --cert-name vault.allincruisive.com --force-renewal
```

Or if this is a manual renewal:

```bash
sudo certbot certonly \
  --manual \
  --preferred-challenges dns \
  --force-renewal \
  -d vault.allincruisive.com
```

When prompted, create the DNS TXT record in GoDaddy, then press Enter.

### Step 2: Get Certificate Content

After renewal completes, read the certificate files:

```bash
# Full chain certificate
sudo cat /etc/letsencrypt/live/vault.allincruisive.com/fullchain.pem

# Private key
sudo cat /etc/letsencrypt/live/vault.allincruisive.com/privkey.pem

# CA chain
sudo cat /etc/letsencrypt/live/vault.allincruisive.com/chain.pem
```

### Step 3: Run GitHub Action

1. Go to https://github.com/dorinahashicorp/vault-enterprise/actions
2. Click **"Renew Vault TLS Certificate"** in the left sidebar
3. Click **"Run workflow"** button (top right)
4. Paste the certificate content into the three input fields:
   - **cert_fullchain**: Paste fullchain.pem content
   - **cert_privkey**: Paste privkey.pem content
   - **cert_chain**: Paste chain.pem content
5. Click **"Run workflow"** (green button)

The workflow will:
- Connect to HCP Terraform API
- Update all three certificate variables
- Show you a success message with next steps

### Step 4: Apply in HCP Terraform

1. Go to https://app.terraform.io/app/Infragoose/workspaces/vault-enterprise
2. Click **Variables** tab to verify the certificates were updated
3. Click **Actions** → **Start new run**
4. Review the plan (should show only secrets manager updates)
5. Click **Confirm & Apply**

Vault will automatically reload with the new certificates. No downtime!

## Checking Certificate Expiry

To check when your certificate expires:

```bash
echo | openssl s_client -servername vault.allincruisive.com \
  -connect vault.allincruisive.com:8200 2>/dev/null \
  | openssl x509 -noout -dates
```

## Setting a Reminder

Set a calendar reminder for 60 days from now to renew the certificate.

Or use this one-liner to calculate the date:

```bash
date -v+60d  # macOS
date -d "+60 days"  # Linux
```

## Alternative: Use the Shell Script

If you prefer not to use GitHub Actions, you can use the shell script:

```bash
cd scripts
export HCP_TERRAFORM_TOKEN="your-token"
./renew-vault-cert.sh
```

This does everything in one command (see [scripts/README.md](scripts/README.md)).

## Troubleshooting

### GitHub Action Fails

Check the action logs for errors:
- Go to Actions tab → Click on the failed run → Click on "update-certificates" job
- Look for error messages

Common issues:
- **Invalid token**: Get a new token from HCP Terraform
- **Workspace not found**: Check org name "Infragoose" and workspace name "vault-enterprise"
- **Variable not found**: The variables must already exist in the workspace

### Certificate Not Loading in Vault

If Vault doesn't pick up the new certificate:
1. Check AWS Secrets Manager was updated (go to AWS Console)
2. Verify the Terraform apply completed successfully
3. Check Vault logs for any errors

### DNS Validation Fails

If certbot DNS validation fails:
- Verify the TXT record was created correctly in GoDaddy
- Wait a few minutes for DNS propagation
- Use `dig _acme-challenge.vault.allincruisive.com TXT` to verify

## Security Notes

- **Protect your HCP Terraform token** - it's stored as a GitHub secret and never exposed in logs
- Never commit certificate files to git (they're already in .gitignore)
- The GitHub Action logs will NOT show certificate content (marked as secrets)
- Only repository admins can access GitHub secrets

## Questions?

See [scripts/README.md](scripts/README.md) for more detailed documentation and alternative automation options.
