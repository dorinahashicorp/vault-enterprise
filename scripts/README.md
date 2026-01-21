# Vault Certificate Automation

This directory contains scripts for automating TLS certificate renewal for your Vault Enterprise deployment.

## Overview

The certificate renewal process:
1. Uses certbot to renew the Let's Encrypt certificate (DNS challenge)
2. Updates certificate variables in HCP Terraform workspace via API
3. Allows you to apply changes to update Vault with new certificates

## Setup

### 1. Create HCP Terraform API Token

1. Go to https://app.terraform.io/app/settings/tokens
2. Click "Create an API token"
3. Give it a name like "Certificate Renewal Automation"
4. Copy the token (you won't see it again!)
5. Store it securely

### 2. Configure the Script

Edit `renew-vault-cert.sh` and update these variables:

```bash
DOMAIN="vault.allincruisive.com"        # Your Vault domain
HCP_ORG="Infragoose"                    # Your HCP Terraform organization
HCP_WORKSPACE="vault-enterprise"        # Your workspace name
CERTBOT_EMAIL="your-email@example.com"  # Your email for Let's Encrypt
```

### 3. Test Manual Renewal

First, test the script manually:

```bash
export HCP_TERRAFORM_TOKEN="your-token-here"
./renew-vault-cert.sh
```

The script will:
- Renew the certificate with certbot
- Update the three certificate variables in HCP Terraform
- Print next steps

After running, go to your HCP Terraform workspace and run a plan/apply.

## Automated Renewal with Cron

To automate certificate renewal every 60 days, add a cron job:

### Option 1: Cron Job (Linux/macOS)

1. Create a secure file to store your token:

```bash
sudo mkdir -p /etc/vault-cert-renewal
sudo chmod 700 /etc/vault-cert-renewal
echo "HCP_TERRAFORM_TOKEN=your-token-here" | sudo tee /etc/vault-cert-renewal/config
sudo chmod 600 /etc/vault-cert-renewal/config
```

2. Create a wrapper script:

```bash
sudo tee /usr/local/bin/vault-cert-renewal-wrapper.sh > /dev/null <<'EOF'
#!/bin/bash
source /etc/vault-cert-renewal/config
cd /path/to/vault-enterprise-1/scripts
./renew-vault-cert.sh >> /var/log/vault-cert-renewal.log 2>&1
EOF

sudo chmod +x /usr/local/bin/vault-cert-renewal-wrapper.sh
```

3. Add to crontab:

```bash
sudo crontab -e
```

Add this line to run every 60 days at 3 AM:

```cron
0 3 */60 * * /usr/local/bin/vault-cert-renewal-wrapper.sh
```

### Option 2: GitHub Actions (Recommended)

For a cloud-based solution, use GitHub Actions:

1. Add your HCP Terraform token as a GitHub secret:
   - Go to your repo → Settings → Secrets and variables → Actions
   - Add secret: `HCP_TERRAFORM_TOKEN`

2. Create `.github/workflows/renew-certificate.yml`:

```yaml
name: Renew Vault Certificate

on:
  schedule:
    # Run every 60 days at 3 AM UTC
    - cron: '0 3 */60 * *'
  workflow_dispatch:  # Allow manual trigger

jobs:
  renew:
    runs-on: ubuntu-latest
    steps:
      - name: Checkout code
        uses: actions/checkout@v4

      - name: Install certbot
        run: |
          sudo apt-get update
          sudo apt-get install -y certbot

      - name: Renew certificate
        env:
          HCP_TERRAFORM_TOKEN: ${{ secrets.HCP_TERRAFORM_TOKEN }}
        run: |
          cd scripts
          ./renew-vault-cert.sh

      - name: Notify completion
        if: success()
        run: echo "Certificate renewed successfully!"
```

### Option 3: AWS Lambda

For a fully cloud-native solution:

1. Create a Lambda function with the renewal script
2. Use EventBridge to trigger it every 60 days
3. Store HCP Terraform token in AWS Secrets Manager
4. Lambda reads token, renews cert, updates HCP Terraform

## Certificate Rotation in Vault

When you apply the Terraform changes with new certificates:

1. **Vault automatically detects the new certificates** from AWS Secrets Manager
2. **No downtime** - Vault performs a graceful reload
3. **No manual intervention** required on the Vault nodes

The HVD module is designed to handle certificate rotation seamlessly.

## Testing Certificate Expiry

To check when your current certificate expires:

```bash
echo | openssl s_client -servername vault.allincruisive.com -connect vault.allincruisive.com:8200 2>/dev/null | openssl x509 -noout -dates
```

## Monitoring

Set up monitoring to alert you if:
- Certificate is within 30 days of expiry (backup alert)
- Renewal script fails
- Terraform apply fails after renewal

You can use:
- AWS CloudWatch for logs
- GitHub Actions notifications
- Email alerts from cron
- External certificate monitoring services (SSL Labs, etc.)

## Troubleshooting

### Certificate renewal fails

Check certbot logs:
```bash
sudo cat /var/log/letsencrypt/letsencrypt.log
```

### HCP Terraform API call fails

- Verify token is valid: https://app.terraform.io/app/settings/tokens
- Check token has workspace access
- Ensure workspace name and org are correct

### Terraform apply fails

- Review the plan in HCP Terraform UI
- Check AWS Secrets Manager has been updated
- Verify Vault instances can reach Secrets Manager endpoints

## Manual Certificate Renewal

If automation fails, you can always renew manually:

1. Run certbot manually:
   ```bash
   sudo certbot renew --cert-name vault.allincruisive.com --force-renewal
   ```

2. Copy certificate files to your local machine

3. Update HCP Terraform variables manually in the UI

4. Run Terraform apply

## Security Notes

- **Protect the HCP Terraform token** - it has write access to your workspace
- Store token in secure locations (never commit to git)
- Use principle of least privilege - token should only access the Vault workspace
- Rotate the API token periodically
- Enable MFA on your HCP Terraform account

## Cost Considerations

- Let's Encrypt certificates are **free**
- DNS challenge validation requires manual DNS updates unless you automate with Route53/CloudFlare API
- HCP Terraform API calls are free
- Automation compute costs are minimal (GitHub Actions free tier is sufficient)

## Alternative: Commercial Certificate

If automation complexity is too high, consider a 1-year commercial certificate from:
- DigiCert ($200-300/year)
- Sectigo ($50-100/year)
- GoDaddy ($80-150/year)

These provide 1-year validity and 24/7 support.
