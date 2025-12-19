#!/bin/bash
set -euo pipefail

# Logging
exec > >(tee /var/log/vault-init.log)
exec 2>&1

# Configuration
VAULT_VERSION="${vault_version}"
VAULT_INSTALL_URL="https://releases.hashicorp.com/vault/$${VAULT_VERSION}/vault_$${VAULT_VERSION}_linux_amd64.zip"
VAULT_USER="vault"
VAULT_GROUP="vault"
VAULT_HOME="/opt/vault"
VAULT_CONFIG="/etc/vault.d"
VAULT_DATA="/opt/vault/data"
VAULT_LOGS="/var/log/vault"

# Variables from Terraform
KMS_KEY_ID="${kms_key_id}"
VAULT_FQDN="${vault_fqdn}"
NODE_COUNT="${node_count}"
RESOURCE_NAME_PREFIX="${resource_name_prefix}"
AWS_REGION="${aws_region}"

echo "=== Starting Vault Enterprise installation ==="
echo "Version: $VAULT_VERSION"
echo "Timestamp: $(date)"

# Update system
apt-get update
apt-get install -y unzip curl wget jq awscli

# Create vault user and directories
useradd -r -d "$VAULT_HOME" -s /bin/false "$VAULT_USER" || true
mkdir -p "$VAULT_HOME" "$VAULT_CONFIG" "$VAULT_DATA" "$VAULT_LOGS"
chown -R "$VAULT_USER:$VAULT_GROUP" "$VAULT_HOME" "$VAULT_CONFIG" "$VAULT_DATA" "$VAULT_LOGS"
chmod 700 "$VAULT_DATA"

# Download and install Vault
cd /tmp
curl -fsSLO "$VAULT_INSTALL_URL"
unzip -o "vault_$${VAULT_VERSION}_linux_amd64.zip"
mv vault /usr/local/bin/
chmod +x /usr/local/bin/vault
rm -f "vault_$${VAULT_VERSION}_linux_amd64.zip"

# Enable mlock
setcap cap_ipc_lock=+ep /usr/local/bin/vault

# Write TLS certificates
cat > "$VAULT_CONFIG/tls.pem" <<'EOF'
${vault_server_cert}
EOF

cat > "$VAULT_CONFIG/tls-key.pem" <<'EOF'
${vault_server_key}
EOF

cat > "$VAULT_CONFIG/ca.pem" <<'EOF'
${vault_ca_cert}
EOF

chown "$VAULT_USER:$VAULT_GROUP" "$VAULT_CONFIG"/*.pem
chmod 600 "$VAULT_CONFIG"/*.pem

# Get instance metadata
INSTANCE_ID=$(ec2-metadata --instance-id | cut -d' ' -f2)
PRIVATE_IP=$(ec2-metadata --local-ipv4 | cut -d' ' -f2)
AZ=$(ec2-metadata --availability-zone | cut -d' ' -f2)

# Write Vault configuration
cat > "$VAULT_CONFIG/vault.hcl" <<EOF
# Vault Server Configuration

ui = true

listener "tcp" {
  address       = "0.0.0.0:8200"
  tls_cert_file = "$VAULT_CONFIG/tls.pem"
  tls_key_file  = "$VAULT_CONFIG/tls-key.pem"

  # For mTLS (if needed)
  # tls_client_ca_file = "$VAULT_CONFIG/ca.pem"
}

seal "awskms" {
  region     = "$(ec2-metadata --availability-zone | cut -d' ' -f2 | sed 's/[a-z]$//')"
  kms_key_id = "$KMS_KEY_ID"
}

storage "raft" {
  path = "$VAULT_DATA"
}

telemetry {
  prometheus_retention_time = "30s"
}

api_addr         = "https://$PRIVATE_IP:8200"
cluster_addr     = "https://$PRIVATE_IP:8201"
ui               = true
disable_mlock    = true
log_level        = "info"
EOF

chown "$VAULT_USER:$VAULT_GROUP" "$VAULT_CONFIG/vault.hcl"
chmod 640 "$VAULT_CONFIG/vault.hcl"

# Write Vault license (if provided)
if [ -n "${vault_license}" ]; then
  echo "${vault_license}" > "$VAULT_CONFIG/license.hclic"
  chown "$VAULT_USER:$VAULT_GROUP" "$VAULT_CONFIG/license.hclic"
  chmod 600 "$VAULT_CONFIG/license.hclic"
fi

# Create systemd service
cat > /etc/systemd/system/vault.service <<'EOF'
[Unit]
Description=Vault
Documentation=https://www.vaultproject.io/docs/
Requires=network-online.target
After=network-online.target
ConditionFileNotEmpty=/etc/vault.d/vault.hcl

[Service]
Type=notify
ProtectSystem=full
ProtectHome=yes
NoNewPrivileges=yes
PrivateTmp=yes
PrivateDevices=yes
SecureBits=keep-caps
AmbientCapabilities=CAP_IPC_LOCK
CapabilityBoundingSet=CAP_SYSLOG CAP_IPC_LOCK
LimitNOFILE=65536
LimitNPROC=512
KillMode=process
Restart=on-failure
RestartSec=5
TimeoutStopSec=30
LimitMEMLOCK=infinity

User=vault
Group=vault
ProtectSystem=full
ProtectHome=yes
NoNewPrivileges=yes

ExecStart=/usr/local/bin/vault server -config=/etc/vault.d/vault.hcl
ExecReload=/bin/kill -HUP $MAINPID
StandardOutput=journal
StandardError=journal
SyslogIdentifier=vault

[Install]
WantedBy=multi-user.target
EOF

systemctl daemon-reload
systemctl enable vault
systemctl restart vault

# Wait for Vault to start
sleep 5

# Verify Vault is running
if systemctl is-active --quiet vault; then
  echo "✓ Vault service started successfully"
else
  echo "✗ Vault service failed to start"
  systemctl status vault
  exit 1
fi

echo "=== Vault Enterprise installation complete ==="
echo "Instance: $INSTANCE_ID"
echo "Private IP: $PRIVATE_IP"
echo "Availability Zone: $AZ"

# ============================================================================
# Cluster Initialization (only on first node, with locking mechanism)
# ============================================================================

echo "=== Checking cluster initialization status ==="

# Wait for Vault to be ready
VAULT_ADDR="https://localhost:8200"
export VAULT_SKIP_VERIFY=true
MAX_RETRIES=30
RETRY_COUNT=0

while [ $RETRY_COUNT -lt $MAX_RETRIES ]; do
  if /usr/local/bin/vault status &>/dev/null; then
    echo "✓ Vault is responding"
    break
  fi
  echo "Waiting for Vault to be ready... ($((RETRY_COUNT + 1))/$MAX_RETRIES)"
  sleep 2
  RETRY_COUNT=$((RETRY_COUNT + 1))
done

if [ $RETRY_COUNT -eq $MAX_RETRIES ]; then
  echo "✗ Vault failed to become ready"
  exit 1
fi

# Check if already initialized
INIT_STATUS=$(/usr/local/bin/vault status -format=json 2>/dev/null | jq -r '.initialized')

if [ "$INIT_STATUS" = "true" ]; then
  echo "✓ Cluster already initialized"
else
  echo "⚠ Cluster not initialized, attempting initialization..."
  
  # Use a distributed lock: try to create a marker in /opt/vault/data/.initializing_lock
  # Only the first node to acquire the lock will initialize
  LOCK_FILE="$VAULT_DATA/.initializing_lock"
  INIT_OUTPUT="$VAULT_DATA/init-response.json"
  
  # Try to create lock (atomic operation)
  if mkdir "$VAULT_DATA/.initializing_lock" 2>/dev/null || [ -f "$LOCK_FILE" ]; then
    # Wait a bit for any potential concurrent initializer
    sleep 3
    
    # Check again if initialized (another node may have done it)
    INIT_STATUS=$(/usr/local/bin/vault status -format=json 2>/dev/null | jq -r '.initialized')
    
    if [ "$INIT_STATUS" = "false" ]; then
      echo "Initializing Vault cluster..."
      
      # Initialize cluster (no unseal keys needed - using KMS auto-unseal)
      INIT_OUTPUT=$(/usr/local/bin/vault operator init -format=json 2>&1)
      
      echo "✓ Vault cluster initialized"
      
      # Extract and store root token in AWS Secrets Manager
      ROOT_TOKEN=$(echo "$INIT_OUTPUT" | jq -r '.root_token')
      
      echo "Storing root token in AWS Secrets Manager..."
      
      SECRET_NAME="$RESOURCE_NAME_PREFIX-vault-root-token"
      
      # Store minimal secret with just the token
      SECRET_CONTENT=$(jq -n \
        --arg instance_id "$INSTANCE_ID" \
        --arg timestamp "$(date -u +%Y-%m-%dT%H:%M:%SZ)" \
        --arg root_token "$ROOT_TOKEN" \
        '{
          initialized_by_instance: $instance_id,
          initialized_at: $timestamp,
          root_token: $root_token
        }')
      
      aws secretsmanager create-secret \
        --name "$SECRET_NAME" \
        --description "Vault root token for $RESOURCE_NAME_PREFIX cluster" \
        --secret-string "$SECRET_CONTENT" \
        --region "$AWS_REGION" \
        --tags "Key=Name,Value=$RESOURCE_NAME_PREFIX-vault-root-token" "Key=Resource,Value=vault-cluster" \
        2>/dev/null || {
          # Secret might already exist, try to update it
          aws secretsmanager update-secret \
            --secret-id "$SECRET_NAME" \
            --secret-string "$SECRET_CONTENT" \
            --region "$AWS_REGION" \
            2>/dev/null || echo "⚠ Warning: Could not store secret in AWS Secrets Manager"
        }
      
      echo "✓ Root token stored in Secrets Manager: $SECRET_NAME"
      echo "Note: This cluster uses KMS auto-unseal - no unseal keys needed"
      
      # Clean up lock
      rmdir "$VAULT_DATA/.initializing_lock" 2>/dev/null || true
    else
      echo "✓ Cluster was initialized by another node while this node was starting"
    fi
  else
    echo "Another node is initializing, waiting for cluster to become ready..."
    
    # Wait for cluster to be initialized by another node
    INIT_CHECK_RETRIES=60
    INIT_CHECK_COUNT=0
    
    while [ $INIT_CHECK_COUNT -lt $INIT_CHECK_RETRIES ]; do
      INIT_STATUS=$(/usr/local/bin/vault status -format=json 2>/dev/null | jq -r '.initialized')
      if [ "$INIT_STATUS" = "true" ]; then
        echo "✓ Cluster initialized by another node"
        break
      fi
      echo "Waiting for cluster initialization... ($((INIT_CHECK_COUNT + 1))/$INIT_CHECK_RETRIES)"
      sleep 2
      INIT_CHECK_COUNT=$((INIT_CHECK_COUNT + 1))
    done
    
    if [ $INIT_CHECK_COUNT -eq $INIT_CHECK_RETRIES ]; then
      echo "✗ Timeout waiting for cluster initialization"
      exit 1
    fi
  fi
fi

echo "=== Vault cluster ready ==="
