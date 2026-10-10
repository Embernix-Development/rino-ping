#!/usr/bin/env bash

set -e

INSTALL_DIR="/usr/local/bin"
CONFIG_DIR="/etc/rino-ping"
SERVICE_FILE="/etc/systemd/system/rino-ping.service"
BINARY_NAME="rino-ping"

if [ "$(id -u)" -ne 0 ]; then
    echo "Please run as root."
    exit 1
fi

systemctl stop \
    rino-ping \
    2>/dev/null || true

systemctl disable \
    rino-ping \
    2>/dev/null || true

rm -f \
    "$SERVICE_FILE"

rm -f \
    "$INSTALL_DIR/$BINARY_NAME"

rm -rf \
    "$CONFIG_DIR"

systemctl daemon-reload

echo "Rino Ping Agent removed."