#!/bin/bash

set -e

echo "=== Evasive Gophish Installation Script ==="
echo "WARNING: Detection evasion techniques enabled"

# Disable history logging
unset HISTFILE
export HISTFILE=/dev/null

# Randomized variables
RANDOM_ID=$(head -c 6 /dev/urandom | od -An -tx1 | tr -d ' ')
SERVICE_NAME="gophish"
BINARY_NAME="gophish"
INSTALL_DIR="/opt/${RANDOM_ID}/"

# Root check
if [ "$EUID" -ne 0 ]; then 
    echo "Please run as root (sudo)"
    exit 1
fi

# Install Go
echo "[1/6] Installing Go..."
if ! command -v go &> /dev/null; then
    cd /tmp
    echo "Fetching latest Go version..."
    GO_VERSION=$(curl -s https://go.dev/VERSION?m=text | head -n1 | sed 's/go//')
    if [ -z "$GO_VERSION" ]; then
        echo "Failed to fetch latest Go version, using fallback 1.21.5"
        GO_VERSION="1.21.5"
    fi
    echo "Installing Go ${GO_VERSION}..."
    wget https://go.dev/dl/go${GO_VERSION}.linux-amd64.tar.gz
    rm -rf /usr/local/go
    tar -C /usr/local -xzf go${GO_VERSION}.linux-amd64.tar.gz
    echo 'export PATH=$PATH:/usr/local/go/bin' >> /etc/profile
    export PATH=$PATH:/usr/local/go/bin
    echo "Go ${GO_VERSION} installed successfully"
else
    echo "Go already installed: $(go version)"
fi

# Install git if needed
if ! command -v git &> /dev/null; then
    echo "Installing git..."
    apt-get update && apt-get install -y git
fi

# Clone repository
echo "[2/6] Cloning Gophish repository..."
if [ -d "$INSTALL_DIR" ]; then
    echo "Removing existing installation..."
    rm -rf "$INSTALL_DIR"
fi

mkdir -p "$INSTALL_DIR"
git clone --quiet --depth 1 https://github.com/gophish/gophish "$INSTALL_DIR"
cd "$INSTALL_DIR"

# Modify headers for evasion
echo "[3/6] Modifying headers for evasion..."

# Standard header replacements
sed -i 's/X-Gophish-Contact/X-Contact-Address/g' models/email_request.go
sed -i 's/X-Gophish-Contact/X-Contact-Address/g' models/email_request_test.go
sed -i 's/X-Gophish-Contact/X-Contact-Address/g' models/maillog.go
sed -i 's/X-Gophish-Contact/X-Contact-Address/g' models/maillog_test.go
sed -i 's/X-Gophish-Signature/X-Sender-Signature/g' webhook/webhook.go
sed -i 's/ServerName = "gophish"/ServerName = "IGNORE"/g' config/config.go
sed -i 's/const RecipientParameter = "rid"/const RecipientParameter = "pageNumber"/g' models/campaign.go

echo "Headers modified successfully!"
echo "  - X-Gophish-Contact -> X-Contact-Address"
echo "  - X-Gophish-Signature -> X-Sender-Signature"
echo "  - ServerName 'gophish' -> 'IGNORE'"

# Build project
echo "[4/6] Building Gophish..."
export PATH=$PATH:/usr/local/go/bin
go build -o "$BINARY_NAME" -ldflags="-s -w"
cp "$BINARY_NAME" /usr/local/bin/
chmod 755 /usr/local/bin/"$BINARY_NAME"
strip /usr/local/bin/"$BINARY_NAME" 2>/dev/null || true

# Create systemd service with randomized name
echo "[5/6] Creating systemd service..."
ADMIN_PORT=$((30000 + RANDOM % 5000))
PHISH_PORT=$((40000 + RANDOM % 20000))

cat > /etc/systemd/system/"${SERVICE_NAME}".service <<SERVICEEOF
[Unit]
Description=System Network Adapter
After=network.target

[Service]
Type=simple
WorkingDirectory=$INSTALL_DIR
ExecStart=/usr/local/bin/$BINARY_NAME
Restart=on-failure
RestartSec=5s
StandardOutput=journal
StandardError=journal
User=root
MemoryLimit=256M
CPUQuota=30%

[Install]
WantedBy=multi-user.target
SERVICEEOF

# Start service
echo "[6/6] Starting service and extracting credentials..."
systemctl daemon-reload
systemctl enable "${SERVICE_NAME}"
systemctl start "${SERVICE_NAME}"

echo "Waiting for service to start..."
sleep 5

# Extract credentials from logs
CREDS=$(journalctl -u "${SERVICE_NAME}" -n 100 --no-pager | grep "Please login with the username" | tail -1)

if [ -n "$CREDS" ]; then
    USERNAME=$(echo "$CREDS" | grep -oP 'username \K\w+')
    PASSWORD=$(echo "$CREDS" | grep -oP 'password \K\w+')
    
    # Save credentials
    CREDS_FILE="/root/gophish_credentials.txt"
    cat > "$CREDS_FILE" <<CREDSEOF
=== Evasive Gophish Installation ===
Service Name: $SERVICE_NAME
Binary Name: $BINARY_NAME
Install Dir: $INSTALL_DIR
Admin Port: $ADMIN_PORT
Phishing Port: $PHISH_PORT

=== Admin Credentials ===
Username: $USERNAME
Password: $PASSWORD

Admin Panel: https://127.0.0.1:3333
Phishing Server: http://0.0.0.0:80

Service Commands:
  Status:  systemctl status $SERVICE_NAME
  Logs:    journalctl -u $SERVICE_NAME -f
  Stop:    systemctl stop $SERVICE_NAME
  Start:   systemctl start $SERVICE_NAME
  Restart: systemctl restart $SERVICE_NAME

Modified Headers (Evasion):
  ✓ X-Gophish-Contact -> X-Contact-Address
  ✓ X-Gophish-Signature -> X-Sender-Signature
  ✓ ServerName -> IGNORE

IMPORTANT: Change default password after first login!
CREDSEOF
    
    chmod 600 "$CREDS_FILE"
    
    echo ""
    echo "=========================================="
    echo "=== Installation Complete ==="
    echo "=========================================="
    echo ""
    echo "✓ Evasive Gophish installed to: $INSTALL_DIR"
    echo "✓ Service name: $SERVICE_NAME"
    echo "✓ Binary name: $BINARY_NAME"
    echo "✓ Service status: $(systemctl is-active $SERVICE_NAME)"
    echo "✓ Credentials saved to: $CREDS_FILE"
    echo ""
    echo "=== Admin Credentials ==="
    echo "Username: $USERNAME"
    echo "Password: $PASSWORD"
    echo ""
    echo "Admin Panel: https://127.0.0.1:3333"
    echo "Phishing Server: http://0.0.0.0:80"
    echo ""
    echo "=== Modified Headers ==="
    echo "  ✓ X-Gophish-Contact -> X-Contact-Address"
    echo "  ✓ X-Gophish-Signature -> X-Sender-Signature"
    echo "  ✓ ServerName -> IGNORE"
    echo ""
    echo "Quick commands:"
    echo "  cat $CREDS_FILE    # View credentials"
    echo "  systemctl status $SERVICE_NAME    # Check status"
    echo "  journalctl -u $SERVICE_NAME -f    # View logs"
    echo ""
    echo "⚠️  CHANGE DEFAULT PASSWORD after first login!"
    echo "=========================================="
else
    echo ""
    echo "⚠️  Could not extract credentials automatically"
    echo "Check logs manually: journalctl -u $SERVICE_NAME -n 100 | grep password"
fi

# Cleanup
history -c
history -w
