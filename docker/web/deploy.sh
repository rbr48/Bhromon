#!/bin/bash
set -e
echo "==> Deploying Bhromon Web..."
cd /root/bhromon-web
docker compose up -d --build --force-recreate
echo "==> Deployment complete!"
