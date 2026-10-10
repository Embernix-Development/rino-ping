#!/usr/bin/env bash

set -e

DOMAIN=""
PORT="8443"
NGINX_SITE="/etc/nginx/sites-available/rino-ping"
NGINX_LINK="/etc/nginx/sites-enabled/rino-ping"

while [[ $# -gt 0 ]]; do
    case "$1" in
        --domain)
            DOMAIN="$2"
            shift 2
            ;;
        --port)
            PORT="$2"
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

if [ -z "$DOMAIN" ]; then
    echo "Missing domain."
    echo
    echo "Example:"
    echo "sudo bash setup-wss.sh --domain ping-fra.example.com"
    exit 1
fi

echo
echo "Rino Ping WSS Setup"
echo
echo "Domain: $DOMAIN"
echo "Agent port: $PORT"
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

echo "Creating Nginx configuration..."

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
echo "Rino Ping secure endpoint is ready."
echo
echo "WebSocket:"
echo "wss://$DOMAIN/ping"
echo
echo "Health:"
echo "https://$DOMAIN/health"
echo