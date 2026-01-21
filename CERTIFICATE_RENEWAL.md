# Certificate Renewal Guide

Simple, straightforward instructions to renew your Vault TLS certificate every 60-90 days.

**Total time: ~5-7 minutes**

---

## Step 1: Renew Certificate with Certbot

Open your terminal and run:

```bash
sudo certbot renew --cert-name <YOUR_VAULT_FQDN> --force-renewal
```

Replace `<YOUR_VAULT_FQDN>` with your Vault domain (e.g., `vault.example.com`).

**What happens:**
Certbot will display a DNS challenge. Example:

```
Please deploy a DNS TXT record under the name:
_acme-challenge.<YOUR_VAULT_FQDN>

with the following value:
JoXZAbzxQWNSQDp9G_inF8VWODZbHpNf6OmMqVQL-4s

Press Enter to Continue
```

**Don't press Enter yet!** Go to Step 2.

---

## Step 2: Create DNS TXT Record

1. Go to your DNS provider's management console
2. Click **Add** (or equivalent)
3. Select **TXT** record
4. Fill in:
   - **Name**: `_acme-challenge.vault` (or the subdomain shown by certbot)
   - **Value**: Paste the value from certbot (e.g., `JoXZAbzxQWNSQDp9G_inF8VWODZbHpNf6OmMqVQL-4s`)
   - **TTL**: `600 seconds`
5. Click **Save**
6. Wait 1-2 minutes

**Verify DNS (optional):**
```bash
dig _acme-challenge.<YOUR_VAULT_FQDN> TXT +short
```

Back in your terminal, press **Enter**. Certbot will complete the renewal.

✅ Certificate renewed!

---

## Step 3: Copy Certificate Files

Read the three certificate files:

```bash
# Full chain certificate
sudo cat /etc/letsencrypt/live/<YOUR_VAULT_FQDN>/fullchain.pem

# Private key
sudo cat /etc/letsencrypt/live/<YOUR_VAULT_FQDN>/privkey.pem

# CA chain
sudo cat /etc/letsencrypt/live/<YOUR_VAULT_FQDN>/chain.pem
```

Select and copy each file's complete content (including `-----BEGIN` and `-----END` lines).

---

## Step 4: Update HCP Terraform Variables

1. Go to https://app.terraform.io/app/YOUR_ORG/workspaces/YOUR_WORKSPACE
2. Click **Variables** tab
3. Update these three variables:

### vault_tls_cert
- Click the **⋯** menu → **Edit**
- **Value**: Paste the entire `fullchain.pem` content
- Click **Save variable**

### vault_tls_key
- Click the **⋯** menu → **Edit**
- **Value**: Paste the entire `privkey.pem` content
- Click **Save variable**

### vault_ca_bundle
- Click the **⋯** menu → **Edit**
- **Value**: Paste the entire `chain.pem` content
- Click **Save variable**

✅ Variables updated!

---

## Step 5: Apply Changes

1. In the same workspace, click **Actions** → **Start new run**
2. Click **Start run**
3. Review the plan (should show 3 AWS Secrets Manager updates)
4. Click **Confirm & Apply**
5. Add comment: `Certificate renewal - expires [90 days from today]`
6. Click **Confirm plan**
7. Wait 1-2 minutes for apply to complete

Vault instances automatically reload with new certificates. **No downtime!**

✅ Done!

---

## Step 6: Clean Up (Optional)

Delete the temporary TXT record from your DNS provider:
1. Go to your DNS management console
2. Find TXT record: `_acme-challenge.vault`
3. Delete the record and save changes

---

## When to Renew

Set a calendar reminder for **60 days from today**.

Calculate reminder date:
```bash
date -v+60d  # macOS
date -d "+60 days"  # Linux
```

---

## Check Certificate Expiry

```bash
echo | openssl s_client -servername <YOUR_VAULT_FQDN> \
  -connect <YOUR_VAULT_FQDN>:8200 2>/dev/null \
  | openssl x509 -noout -dates
```

---

## Troubleshooting

### DNS Validation Fails

- Verify TXT record in your DNS provider matches certbot's value exactly
- Wait 2-3 minutes for DNS propagation
- Use `dig _acme-challenge.<YOUR_VAULT_FQDN> TXT +short` to verify

### Vault Not Using New Certificate

1. Check AWS Secrets Manager was updated (AWS Console → Secrets Manager)
2. Verify Terraform apply completed (HCP Terraform → Runs tab)
3. If needed, restart Vault:
   ```bash
   aws ssm start-session --target i-INSTANCEID --region us-east-1
   sudo systemctl restart vault
   ```

---

## Summary

**Every 60-90 days:**
1. Run certbot (3 min) - Create DNS TXT record when prompted
2. Copy 3 cert files (1 min)
3. Update 3 HCP Terraform variables (1-2 min)
4. Apply changes (1-2 min)

**Total: 5-7 minutes**

Simple, straightforward, no extra tools or secrets to manage.
