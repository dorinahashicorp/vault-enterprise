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
