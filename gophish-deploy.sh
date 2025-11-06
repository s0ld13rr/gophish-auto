#!/bin/bash

set -e

echo "=== Gophish PoC Installation Script ==="
echo "WARNING: This modifies headers for security testing"

# Проверка прав root
if [ "$EUID" -ne 0 ]; then 
    echo "Please run as root (sudo)"
    exit 1
fi

# Установка Go
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

# Установка git если нужно
if ! command -v git &> /dev/null; then
    echo "Installing git..."
    apt-get update && apt-get install -y git
fi

# Клонирование репозитория
echo "[2/6] Cloning Gophish repository..."
INSTALL_DIR="/opt/gophish"
if [ -d "$INSTALL_DIR" ]; then
    echo "Removing existing installation..."
    rm -rf "$INSTALL_DIR"
fi

git clone https://github.com/gophish/gophish "$INSTALL_DIR"
cd "$INSTALL_DIR"

# Модификация заголовков для PoC
echo "[3/6] Modifying headers for PoC..."

# models/email_request.go
sed -i 's/X-Gophish-Contact/X-Contact-Address/g' models/email_request.go

# models/email_request_test.go
sed -i 's/X-Gophish-Contact/X-Contact-Address/g' models/email_request_test.go

# models/maillog.go
sed -i 's/X-Gophish-Contact/X-Contact-Address/g' models/maillog.go

# models/maillog_test.go
sed -i 's/X-Gophish-Contact/X-Contact-Address/g' models/maillog_test.go

# webhook/webhook.go
sed -i 's/X-Gophish-Signature/X-Sender-Signature/g' webhook/webhook.go

# config/config.go - ServerName
sed -i 's/ServerName = "gophish"/ServerName = "Exchange Server"/g' config/config.go

sed -i 's/const RecipientParameter = "rid"/const RecipientParameter = "pageNumber"/g' models/campaign.go

echo "Headers modified successfully!"
echo "  - X-Gophish-Contact -> X-Contact-Address"
echo "  - X-Gophish-Signature -> X-Sender-Signature"
echo "  - ServerName 'gophish' -> 'Exchange Server'"

# Сборка проекта
echo "[4/6] Building Gophish..."
export PATH=$PATH:/usr/local/go/bin
go build

# Создание systemd сервиса
echo "[5/6] Creating systemd service..."
cat > /etc/systemd/system/gophish.service <<'SERVICEEOF'
[Unit]
Description=Gophish PoC Server
After=network.target

[Service]
Type=simple
WorkingDirectory=/opt/gophish
ExecStart=/opt/gophish/gophish
Restart=on-failure
RestartSec=5s
StandardOutput=journal
StandardError=journal

[Install]
WantedBy=multi-user.target
SERVICEEOF

# Включение и запуск сервиса
echo "[6/6] Starting service and extracting credentials..."
systemctl daemon-reload
systemctl enable gophish
systemctl start gophish

# Ждем запуска и извлекаем credentials
echo "Waiting for service to start..."
sleep 5

# Извлечение credentials из логов
CREDS=$(journalctl -u gophish -n 100 --no-pager | grep "Please login with the username" | tail -1)

if [ -n "$CREDS" ]; then
    USERNAME=$(echo "$CREDS" | grep -oP 'username \K\w+')
    PASSWORD=$(echo "$CREDS" | grep -oP 'password \K\w+')
    
    # Сохраняем credentials в файл
    CREDS_FILE="/root/gophish_credentials.txt"
    cat > "$CREDS_FILE" <<CREDSEOF
=== Gophish Admin Credentials ===
Username: $USERNAME
Password: $PASSWORD
Admin Panel: https://127.0.0.1:3333
Phishing Server: http://0.0.0.0:80

Installation: $INSTALL_DIR
Service: gophish.service

Commands:
  Status:  systemctl status gophish
  Logs:    journalctl -u gophish -f
  Stop:    systemctl stop gophish
  Start:   systemctl start gophish
  Restart: systemctl restart gophish

Modified Headers (PoC):
  ✓ X-Gophish-Contact -> X-Contact-Address
  ✓ X-Gophish-Signature -> X-Sender-Signature
  ✓ ServerName -> Exchange Server

⚠️  IMPORTANT: Change default password after first login!
⚠️  This is a PoC with obvious security detection markers!
CREDSEOF

    chmod 600 "$CREDS_FILE"
    
    echo ""
    echo "=========================================="
    echo "=== Installation Complete ==="
    echo "=========================================="
    echo ""
    echo "✓ Gophish PoC installed to: $INSTALL_DIR"
    echo "✓ Service status: $(systemctl is-active gophish)"
    echo "✓ Credentials saved to: $CREDS_FILE"
    echo ""
    echo "=== Admin Credentials ==="
    echo "Username: $USERNAME"
    echo "Password: $PASSWORD"
    echo ""
    echo "Admin Panel: https://127.0.0.1:3333"
    echo "Phishing Server: http://0.0.0.0:80"
    echo ""
    echo "=== Modified Headers (PoC) ==="
    echo "  ✓ X-Gophish-Contact -> X-Contact-Address"
    echo "  ✓ X-Gophish-Signature -> X-Sender-Signature"
    echo "  ✓ ServerName -> Exchange Server"
    echo ""
    echo "Quick commands:"
    echo "  cat $CREDS_FILE    # View credentials"
    echo "  systemctl status gophish    # Check status"
    echo "  journalctl -u gophish -f    # View logs"
    echo ""
    echo "⚠️  CHANGE DEFAULT PASSWORD after first login!"
    echo "=========================================="
else
    echo ""
    echo "⚠️  Could not extract credentials automatically"
    echo "Check logs manually: journalctl -u gophish -n 100 | grep password"
fi