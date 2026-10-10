#!/usr/bin/env bash

set -e

REPO="Embernix-Development/rino-ping"

INSTALL_DIR="/usr/local/bin"
CONFIG_DIR="/etc/rino-ping"
SERVICE_FILE="/etc/systemd/system/rino-ping.service"
NGINX_SITE="/etc/nginx/sites-available/rino-ping"
NGINX_LINK="/etc/nginx/sites-enabled/rino-ping"

BINARY_NAME="rino-ping"

PORT="8443"
DOMAIN=""

while [[ $# -gt 0 ]]; do
    case "$1" in
        --port)
            PORT="$2"
            shift 2
            ;;

        --domain)
            DOMAIN="$2"
            shift 2
            ;;

        *)
            echo "Unknown option: $1"
            exit 1
            ;;
    esac
done

if [ "$(id -u)" -ne 0 ]; then
    echo "Please run as root."
    exit 1
fi

ARCH="$(uname -m)"

case "$ARCH" in
    x86_64)
        ARCH="amd64"
        ;;

    aarch64|arm64)
        ARCH="arm64"
        ;;

    *)
        echo "Unsupported architecture: $ARCH"
        exit 1
        ;;
esac

echo
echo "Rino Ping Agent"
echo "---------------"
echo
echo "Architecture: $ARCH"
echo "Port: $PORT"

if [ -n "$DOMAIN" ]; then
    echo "Domain: $DOMAIN"
fi

echo

if ! command -v curl >/dev/null 2>&1; then
    echo "Installing curl..."

    apt-get update
    apt-get install -y curl
fi

echo "Finding latest release..."

LATEST_URL="$(
    curl -fsSL \
        "https://api.github.com/repos/$REPO/releases/latest" \
    |
    grep "browser_download_url" \
    |
    grep "rino-ping-linux-$ARCH" \
    |
    cut -d '"' -f 4 \
    |
    head -n 1
)"

if [ -z "$LATEST_URL" ]; then
    echo "Could not find a compatible Rino Ping Agent release."
    exit 1
fi

echo "Downloading Rino Ping Agent..."

curl -fL \
    "$LATEST_URL" \
    -o "$INSTALL_DIR/$BINARY_NAME"

chmod +x \
    "$INSTALL_DIR/$BINARY_NAME"

mkdir -p \
    "$CONFIG_DIR"

cat > "$CONFIG_DIR/config.env" <<EOF
PORT=$PORT
EOF

cat > "$SERVICE_FILE" <<EOF
[Unit]
Description=Rino Ping Agent
After=network.target

[Service]
Type=simple
EnvironmentFile=$CONFIG_DIR/config.env
ExecStart=$INSTALL_DIR/$BINARY_NAME --port \${PORT}
Restart=always
RestartSec=2
User=root

[Install]
WantedBy=multi-user.target
EOF

systemctl daemon-reload

systemctl enable \
    rino-ping

systemctl restart \
    rino-ping

echo
echo "Rino Ping Agent installed."
echo

if ! systemctl is-active --quiet rino-ping; then
    echo "Rino Ping Agent failed to start."
    echo
    echo "Check logs with:"
    echo "journalctl -u rino-ping -n 50"
    exit 1
fi

if [ -z "$DOMAIN" ]; then
    echo "Agent is running."
    echo
    echo "Health:"
    echo "http://SERVER_IP:$PORT/health"
    echo
    echo "WebSocket:"
    echo "ws://SERVER_IP:$PORT/ping"
    echo
    echo "For production HTTPS websites, install again with:"
    echo
    echo "curl -fsSL https://raw.githubusercontent.com/$REPO/main/install.sh | sudo bash -s -- --domain ping.example.com"
    echo
    exit 0
fi

echo "Setting up secure WSS endpoint..."
echo

if ! command -v nginx >/dev/null 2>&1; then
    echo "Installing Nginx..."

    apt-get update
    apt-get install -y nginx
fi

if ! command -v certbot >/dev/null 2>&1; then
    echo "Installing Certbot..."

    apt-get update

    apt-get install -y \
        certbot \
        python3-certbot-nginx
fi

cat > "$NGINX_SITE" <<EOF
server {
    listen 80;
    listen [::]:80;

    server_name $DOMAIN;

    location /ping {
        proxy_pass http://127.0.0.1:$PORT;

        proxy_http_version 1.1;

        proxy_set_header Upgrade \$http_upgrade;
        proxy_set_header Connection "upgrade";

        proxy_set_header Host \$host;
        proxy_set_header X-Real-IP \$remote_addr;
        proxy_set_header X-Forwarded-For \$proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto \$scheme;

        proxy_read_timeout 60s;
        proxy_send_timeout 60s;
    }

    location /health {
        proxy_pass http://127.0.0.1:$PORT;

        proxy_set_header Host \$host;
        proxy_set_header X-Real-IP \$remote_addr;
        proxy_set_header X-Forwarded-For \$proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto \$scheme;
    }
}
EOF

ln -sf \
    "$NGINX_SITE" \
    "$NGINX_LINK"

nginx -t

systemctl enable nginx
systemctl restart nginx

echo
echo "Requesting SSL certificate..."
echo

certbot \
    --nginx \
    -d "$DOMAIN" \
    --non-interactive \
    --agree-tos \
    --register-unsafely-without-email \
    --redirect

nginx -t
systemctl reload nginx

echo
echo "Rino Ping Agent setup complete."
echo
echo "Health:"
echo "https://$DOMAIN/health"
echo
echo "WebSocket:"
echo "wss://$DOMAIN/ping"
echo
echo "Use this in Rino:"
echo
echo "wss://$DOMAIN/ping"
echo