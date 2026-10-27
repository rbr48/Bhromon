#!/usr/bin/env bash
# Bhromon VPS Deployment Script
# Deploys both bhromon-media and bhromon-games microservices on Hostinger VPS (148.135.137.245)

set -euo pipefail

echo "========================================="
echo "   Deploying Bhromon VPS Services        "
echo "========================================="

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(dirname "$SCRIPT_DIR")"

cd "$REPO_ROOT"
echo "[1/4] Pulling latest main branch..."
git fetch origin main
git checkout main
git pull origin main

cd "$SCRIPT_DIR"
echo "[2/4] Building and launching Docker services..."
docker compose build --pull
docker compose up -d --remove-orphans

echo "[3/4] Testing container health..."
sleep 3
# Health check for media service
curl -sf http://127.0.0.1:8210/health > /dev/null && echo "  ✔ bhromon-media is healthy on :8210" || echo "  ✖ bhromon-media health check failed"
# Health check for games service
curl -sf http://127.0.0.1:8220/health > /dev/null && echo "  ✔ bhromon-games is healthy on :8220" || echo "  ✖ bhromon-games health check failed"

echo "[4/4] Updating Nginx configuration..."
if [ -f "/etc/nginx/sites-available/bhromon.fun.conf" ]; then
    sudo cp bhromon.fun.conf /etc/nginx/sites-available/bhromon.fun.conf
    sudo nginx -t && sudo systemctl reload nginx
    echo "  ✔ Nginx reloaded successfully."
else
    echo "  ℹ Nginx config not found in standard path. Please update your Nginx config manually if needed."
fi

echo "========================================="
echo "   Deployment Complete!                  "
echo "========================================="
