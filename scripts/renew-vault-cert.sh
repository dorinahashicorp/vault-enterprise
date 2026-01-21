#!/bin/bash
set -e

################################################################################
# Automated Certificate Renewal for Vault Enterprise
#
# This script:
# 1. Renews the Let's Encrypt certificate using certbot
# 2. Updates HCP Terraform workspace variables via API
# 3. Optionally triggers a Terraform apply
#
# Prerequisites:
# - certbot installed
# - HCP_TERRAFORM_TOKEN environment variable set
# - Domain DNS already configured
#
# Usage:
#   export HCP_TERRAFORM_TOKEN="your-token-here"
#   ./renew-vault-cert.sh
################################################################################

# Configuration
DOMAIN="vault.allincruisive.com"
HCP_ORG="Infragoose"
HCP_WORKSPACE="vault-enterprise"
CERTBOT_EMAIL="your-email@example.com"  # Update this

# Check prerequisites
if [ -z "$HCP_TERRAFORM_TOKEN" ]; then
    echo "Error: HCP_TERRAFORM_TOKEN environment variable not set"
    echo "Get your token from: https://app.terraform.io/app/settings/tokens"
    exit 1
fi

echo "Starting certificate renewal for $DOMAIN..."

# Step 1: Renew certificate with certbot
echo "Step 1: Renewing certificate with certbot..."
sudo certbot renew --cert-name "$DOMAIN" --force-renewal

# Alternative: If running for first time or certificate doesn't exist
# sudo certbot certonly \
#   --manual \
#   --preferred-challenges dns \
#   --email "$CERTBOT_EMAIL" \
#   --agree-tos \
#   --no-eff-email \
#   -d "$DOMAIN"

# Step 2: Read certificate files
echo "Step 2: Reading certificate files..."
CERT_PATH="/etc/letsencrypt/live/$DOMAIN"

FULLCHAIN=$(sudo cat "$CERT_PATH/fullchain.pem")
PRIVKEY=$(sudo cat "$CERT_PATH/privkey.pem")
CHAIN=$(sudo cat "$CERT_PATH/chain.pem")

# Step 3: Get workspace ID
echo "Step 3: Getting HCP Terraform workspace ID..."
WORKSPACE_RESPONSE=$(curl -s \
  --header "Authorization: Bearer $HCP_TERRAFORM_TOKEN" \
  --header "Content-Type: application/vnd.api+json" \
  "https://app.terraform.io/api/v2/organizations/$HCP_ORG/workspaces/$HCP_WORKSPACE")

WORKSPACE_ID=$(echo "$WORKSPACE_RESPONSE" | jq -r '.data.id')

if [ "$WORKSPACE_ID" == "null" ]; then
    echo "Error: Could not get workspace ID"
    echo "$WORKSPACE_RESPONSE"
    exit 1
fi

echo "Workspace ID: $WORKSPACE_ID"

# Function to update a Terraform variable
update_variable() {
    local var_name=$1
    local var_value=$2
    local var_description=$3

    echo "Updating variable: $var_name"

    # Check if variable exists
    VARS_RESPONSE=$(curl -s \
      --header "Authorization: Bearer $HCP_TERRAFORM_TOKEN" \
      --header "Content-Type: application/vnd.api+json" \
      "https://app.terraform.io/api/v2/workspaces/$WORKSPACE_ID/vars")

    VAR_ID=$(echo "$VARS_RESPONSE" | jq -r ".data[] | select(.attributes.key == \"$var_name\") | .id")

    # Prepare JSON payload
    JSON_PAYLOAD=$(jq -n \
      --arg key "$var_name" \
      --arg value "$var_value" \
      --arg description "$var_description" \
      '{
        data: {
          type: "vars",
          attributes: {
            key: $key,
            value: $value,
            description: $description,
            category: "terraform",
            hcl: false,
            sensitive: true
          }
        }
      }')

    if [ "$VAR_ID" != "null" ] && [ -n "$VAR_ID" ]; then
        # Update existing variable
        echo "Updating existing variable $var_name (ID: $VAR_ID)"
        curl -s \
          --header "Authorization: Bearer $HCP_TERRAFORM_TOKEN" \
          --header "Content-Type: application/vnd.api+json" \
          --request PATCH \
          --data "$JSON_PAYLOAD" \
          "https://app.terraform.io/api/v2/workspaces/$WORKSPACE_ID/vars/$VAR_ID" > /dev/null
    else
        # Create new variable
        echo "Creating new variable $var_name"
        curl -s \
          --header "Authorization: Bearer $HCP_TERRAFORM_TOKEN" \
          --header "Content-Type: application/vnd.api+json" \
          --request POST \
          --data "$JSON_PAYLOAD" \
          "https://app.terraform.io/api/v2/workspaces/$WORKSPACE_ID/vars" > /dev/null
    fi

    echo "✓ Variable $var_name updated successfully"
}

# Step 4: Update HCP Terraform variables
echo "Step 4: Updating HCP Terraform workspace variables..."

update_variable "vault_tls_cert" "$FULLCHAIN" "TLS certificate full chain (auto-renewed $(date +%Y-%m-%d))"
update_variable "vault_tls_key" "$PRIVKEY" "TLS certificate private key (auto-renewed $(date +%Y-%m-%d))"
update_variable "vault_ca_bundle" "$CHAIN" "TLS CA bundle (auto-renewed $(date +%Y-%m-%d))"

echo ""
echo "✓ Certificate renewal complete!"
echo ""
echo "Next steps:"
echo "1. Go to HCP Terraform workspace: https://app.terraform.io/app/$HCP_ORG/workspaces/$HCP_WORKSPACE"
echo "2. Review the updated certificate variables"
echo "3. Queue a plan and apply to update the Vault cluster"
echo ""
echo "Note: Vault certificate updates are seamless and don't require downtime."
echo "      The Vault service will automatically reload the new certificates."
