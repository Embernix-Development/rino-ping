#!/usr/bin/env bash

set -e

REPO="Embernix-Development/rino-ping"
INSTALL_DIR="/usr/local/bin"
CONFIG_DIR="/etc/rino-ping"
SERVICE_FILE="/etc/systemd/system/rino-ping.service"
BINARY_NAME="rino-ping"
PORT="8443"

while [[ $# -gt 0 ]]; do
    case "$1" in
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
echo "Rino Ping Agent Installer"
echo
echo "Architecture: $ARCH"
echo "Port: $PORT"
echo

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
    echo "Could not find a compatible release."
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
echo "Rino Ping Agent installed successfully."
echo
echo "Service:"
echo "rino-ping"
echo
echo "Port:"
echo "$PORT"
echo
echo "Health endpoint:"
echo "http://SERVER_IP:$PORT/health"
echo
echo "WebSocket endpoint:"
echo "ws://SERVER_IP:$PORT/ping"
echo
echo "Production sites should use WSS through a reverse proxy."
echo