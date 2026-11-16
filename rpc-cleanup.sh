#!/bin/bash

set -e

echo ""
echo "======================================"
echo " RPC Deployment Cleanup Utility"
echo "======================================"
echo ""

read -p "Domain to remove: " DOMAIN

echo ""
echo "Removing nginx configuration..."
echo ""

rm -f "/etc/nginx/sites-enabled/$DOMAIN"
rm -f "/etc/nginx/sites-available/$DOMAIN"

echo "Done"

echo ""
echo "Removing certbot certificates..."
echo ""

certbot delete \
    --cert-name "$DOMAIN" \
    --non-interactive || true

echo ""
echo "Testing nginx..."
echo ""

nginx -t

systemctl reload nginx

echo ""
echo "Cleanup Complete."
echo ""