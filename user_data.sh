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
HCP_VAULT_ADDR="${hcp_vault_addr}"
HCP_VAULT_NAMESPACE="${hcp_vault_namespace}"
HCP_VAULT_TOKEN_FILE="${hcp_vault_token_file}"
VAULT_KV_MOUNT="${vault_kv_mount}"
VAULT_KV_PATH="${vault_kv_path}"

echo "=== Starting Vault Enterprise installation ==="
echo "Version: $VAULT_VERSION"
echo "Timestamp: $(date)"

# Disable IPv6 to fix apt-get connectivity issues with NAT gateway
sysctl -w net.ipv6.conf.all.disable_ipv6=1
sysctl -w net.ipv6.conf.default.disable_ipv6=1

# Update system
apt-get update
apt-get install -y unzip curl wget jq

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

# Retrieve certificates and license from HCP Vault at runtime
echo "Retrieving Vault configuration from HCP Vault..."
if [ ! -f "$HCP_VAULT_TOKEN_FILE" ]; then
  echo "ERROR: HCP Vault token file not found at $HCP_VAULT_TOKEN_FILE"
  exit 1
fi

HCP_VAULT_TOKEN=$(cat "$HCP_VAULT_TOKEN_FILE")

# Retrieve secrets from HCP Vault KV mount
KV_RESPONSE=$(curl -s \
  -H "X-Vault-Namespace: $HCP_VAULT_NAMESPACE" \
  -H "X-Vault-Token: $HCP_VAULT_TOKEN" \
  "$HCP_VAULT_ADDR/v1/$VAULT_KV_MOUNT/data/$VAULT_KV_PATH" 2>/dev/null || echo "{}")

if [ "$KV_RESPONSE" = "{}" ]; then
  echo "ERROR: Failed to retrieve secrets from HCP Vault"
  exit 1
fi

# Extract certificate values
VAULT_SERVER_CERT=$(echo "$KV_RESPONSE" | jq -r '.data.data.server_cert // empty')
VAULT_SERVER_KEY=$(echo "$KV_RESPONSE" | jq -r '.data.data.server_key // empty')
VAULT_CA_CERT=$(echo "$KV_RESPONSE" | jq -r '.data.data.ca_cert // empty')
VAULT_LICENSE=$(echo "$KV_RESPONSE" | jq -r '.data.data.license // empty')

if [ -z "$VAULT_SERVER_CERT" ] || [ -z "$VAULT_SERVER_KEY" ]; then
  echo "ERROR: Failed to extract certificates from HCP Vault response"
  exit 1
fi

echo "✓ Successfully retrieved secrets from HCP Vault"

# Write TLS certificates
cat > "$VAULT_CONFIG/tls.pem" <<EOF
$VAULT_SERVER_CERT
EOF

cat > "$VAULT_CONFIG/tls-key.pem" <<EOF
$VAULT_SERVER_KEY
EOF

cat > "$VAULT_CONFIG/ca.pem" <<EOF
$VAULT_CA_CERT
EOF

chown "$VAULT_USER:$VAULT_GROUP" "$VAULT_CONFIG"/*.pem
chmod 600 "$VAULT_CONFIG"/*.pem

# Write license if present
if [ -n "$VAULT_LICENSE" ]; then
  echo "$VAULT_LICENSE" > "$VAULT_CONFIG/license.hclic"
  chown "$VAULT_USER:$VAULT_GROUP" "$VAULT_CONFIG/license.hclic"
  chmod 600 "$VAULT_CONFIG/license.hclic"
  echo "✓ License written"
fi
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

# Create a marker to run initialization on first successful start
cat > /opt/vault/run_init.sh <<INIT_SCRIPT
#!/bin/bash
VAULT_ADDR="https://localhost:8200"
export VAULT_SKIP_VERIFY=true
VAULT_DATA="/opt/vault/data"
RESOURCE_NAME_PREFIX="$RESOURCE_NAME_PREFIX"
AWS_REGION="$AWS_REGION"
VAULT_USER="vault"
VAULT_GROUP="vault"

# Wait for Vault to be ready
MAX_RETRIES=30
RETRY_COUNT=0
while [ \$RETRY_COUNT -lt \$MAX_RETRIES ]; do
  if /usr/local/bin/vault status &>/dev/null; then
    INIT_STATUS=\$(/usr/local/bin/vault status -format=json 2>/dev/null | jq -r '.initialized')
    [ "\$INIT_STATUS" = "true" ] && break
  fi
  sleep 2
  RETRY_COUNT=\$((RETRY_COUNT + 1))
done

# Initialize if needed (with distributed lock)
LOCK_FILE="\$VAULT_DATA/.init_lock"
if [ ! -f "\$LOCK_FILE" ] && ! mkdir "\$VAULT_DATA/.init_lock" 2>/dev/null; then
  # Another node is initializing, wait for it
  for i in {1..60}; do
    INIT_STATUS=\$(/usr/local/bin/vault status -format=json 2>/dev/null | jq -r '.initialized')
    [ "\$INIT_STATUS" = "true" ] && break
    sleep 1
  done
  exit 0
fi

INIT_STATUS=\$(/usr/local/bin/vault status -format=json 2>/dev/null | jq -r '.initialized')
[ "\$INIT_STATUS" = "true" ] && { rmdir "\$VAULT_DATA/.init_lock" 2>/dev/null; exit 0; }

# Initialize
INIT_OUTPUT=\$(/usr/local/bin/vault operator init -format=json)
ROOT_TOKEN=\$(echo "\$INIT_OUTPUT" | jq -r '.root_token')

echo "==================================================================="
echo "ROOT TOKEN: \$ROOT_TOKEN"
echo "==================================================================="

# Write root token to file for Terraform data source to read
mkdir -p /opt/vault
echo "\$ROOT_TOKEN" > /opt/vault/root_token.txt
chmod 644 /opt/vault/root_token.txt

rmdir "\$VAULT_DATA/.init_lock" 2>/dev/null
INIT_SCRIPT

chmod 700 /opt/vault/run_init.sh
chown root:root /opt/vault/run_init.sh

# Schedule initialization to run after Vault starts (via systemd timer or cron)
cat > /etc/systemd/system/vault-init.service <<'INIT_SERVICE'
[Unit]
Description=Initialize Vault cluster (runs once on first startup)
After=vault.service
Requires=vault.service

[Service]
Type=oneshot
ExecStart=/opt/vault/run_init.sh
RemainAfterExit=yes
StandardOutput=journal
StandardError=journal

[Install]
WantedBy=multi-user.target
INIT_SERVICE

systemctl daemon-reload
systemctl enable vault-init.service
systemctl start vault-init.service