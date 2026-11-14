#!/bin/bash

set -e

GREEN="\033[0;32m"
RED="\033[0;31m"
NC="\033[0m"

echo ""
echo "=========================================="
echo " Hoodium Mainchain Devnet"
echo " EVM RPC Gateway Installer"
echo "=========================================="
echo ""

read -p "Domain Name: " DOMAIN
read -p "Admin Email: " EMAIL

read -p "Backend RPC IP: " RPC_IP
read -p "Backend RPC Port [8545]: " RPC_PORT

RPC_PORT=${RPC_PORT:-8545}

read -p "Enable WebSocket? (y/n): " ENABLE_WS

if [[ "$ENABLE_WS" =~ ^[Yy]$ ]]; then
    read -p "WebSocket Port [8546]: " WS_PORT
    WS_PORT=${WS_PORT:-8546}
fi

read -p "Enable SSL? (y/n): " ENABLE_SSL
read -p "Enable Authentication? (y/n): " ENABLE_AUTH
read -p "Enable Rate Limiting? (y/n): " ENABLE_RATE
read -p "Enable DDoS Protection? (y/n): " ENABLE_DDOS
read -p "Enable Load Balancing? (y/n): " ENABLE_LB

###################################
# Load Balancer
###################################

if [[ "$ENABLE_LB" =~ ^[Yy]$ ]]; then

    read -p "How many backend RPC nodes? " BACKENDS

    UPSTREAM="upstream rpc_cluster {"

    for ((i=1;i<=BACKENDS;i++)); do

        read -p "Backend $i IP: " BIP
        read -p "Backend $i Port: " BPORT

        UPSTREAM+="
            server ${BIP}:${BPORT} max_fails=3 fail_timeout=30s;"

    done

    UPSTREAM+="
}"

fi

###################################
# Auth
###################################

if [[ "$ENABLE_AUTH" =~ ^[Yy]$ ]]; then

    read -p "Username: " RPC_USER
    read -s -p "Password: " RPC_PASS
    echo ""

fi

###################################
# Rate Limit
###################################

if [[ "$ENABLE_RATE" =~ ^[Yy]$ ]]; then

    read -p "Requests per second [30]: " RATE
    RATE=${RATE:-30}

fi

###################################
# Install
###################################

apt update

apt install -y \
nginx \
certbot \
python3-certbot-nginx \
apache2-utils \
curl \
dnsutils

###################################
# Firewall
###################################

if command -v ufw &> /dev/null; then

    ufw allow 80/tcp
    ufw allow 443/tcp

fi

###################################
# Auth File
###################################

if [[ "$ENABLE_AUTH" =~ ^[Yy]$ ]]; then

htpasswd -bc /etc/nginx/.rpc-auth \
"$RPC_USER" \
"$RPC_PASS"

fi

###################################
# Generate NGINX
###################################

NGINX_CONF="/etc/nginx/sites-available/$DOMAIN"

cat > "$NGINX_CONF" <<EOF

$UPSTREAM

EOF

###################################
# Rate Limit Block
###################################

if [[ "$ENABLE_RATE" =~ ^[Yy]$ ]]; then

cat >> "$NGINX_CONF" <<EOF

limit_req_zone \$binary_remote_addr \
zone=rpc_limit:10m \
rate=${RATE}r/s;

EOF

fi

###################################
# DDoS Connection Limits
###################################

if [[ "$ENABLE_DDOS" =~ ^[Yy]$ ]]; then

cat >> "$NGINX_CONF" <<EOF

limit_conn_zone \$binary_remote_addr \
zone=conn_limit:10m;

EOF

fi

###################################
# Main Server
###################################

cat >> "$NGINX_CONF" <<EOF

server {

    listen 80;

    server_name $DOMAIN;

    location / {

EOF

###################################
# AUTH
###################################

if [[ "$ENABLE_AUTH" =~ ^[Yy]$ ]]; then

cat >> "$NGINX_CONF" <<EOF

        auth_basic "Restricted";
        auth_basic_user_file /etc/nginx/.rpc-auth;

EOF

fi

###################################
# RATE
###################################

if [[ "$ENABLE_RATE" =~ ^[Yy]$ ]]; then

cat >> "$NGINX_CONF" <<EOF

        limit_req zone=rpc_limit burst=50 nodelay;

EOF

fi

###################################
# DDoS
###################################

if [[ "$ENABLE_DDOS" =~ ^[Yy]$ ]]; then

cat >> "$NGINX_CONF" <<EOF

        limit_conn conn_limit 20;

EOF

fi

###################################
# Proxy
###################################

if [[ "$ENABLE_LB" =~ ^[Yy]$ ]]; then

TARGET="http://rpc_cluster"

else

TARGET="http://$RPC_IP:$RPC_PORT"

fi

cat >> "$NGINX_CONF" <<EOF

        proxy_pass ${TARGET};

        proxy_http_version 1.1;

        proxy_set_header Host \$host;
        proxy_set_header X-Real-IP \$remote_addr;
        proxy_set_header X-Forwarded-For \$proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto \$scheme;

        proxy_read_timeout 300;
        proxy_connect_timeout 300;
        proxy_send_timeout 300;
    }

}
EOF

###################################
# Websocket
###################################

if [[ "$ENABLE_WS" =~ ^[Yy]$ ]]; then

cat >> "$NGINX_CONF" <<EOF

server {

    listen 80;

    server_name ws.$DOMAIN;

    location / {

        proxy_pass http://$RPC_IP:$WS_PORT;

        proxy_http_version 1.1;

        proxy_set_header Upgrade \$http_upgrade;
        proxy_set_header Connection "upgrade";

        proxy_set_header Host \$host;

        proxy_read_timeout 86400;
    }

}
EOF

fi

###################################
# Enable Site
###################################

ln -sf \
"$NGINX_CONF" \
"/etc/nginx/sites-enabled/$DOMAIN"

rm -f /etc/nginx/sites-enabled/default

###################################
# Validate
###################################

nginx -t
systemctl restart nginx

###################################
# SSL
###################################

if [[ "$ENABLE_SSL" =~ ^[Yy]$ ]]; then

certbot \
--nginx \
-d "$DOMAIN" \
-m "$EMAIL" \
--agree-tos \
--non-interactive \
--redirect

if [[ "$ENABLE_WS" =~ ^[Yy]$ ]]; then

certbot \
--nginx \
-d "ws.$DOMAIN" \
-m "$EMAIL" \
--agree-tos
--redirect

fi

fi

###################################
# Renewal Test
###################################

certbot renew --dry-run

echo ""
echo -e "${GREEN}Deployment Complete${NC}"
echo ""

echo "RPC Endpoint:"
echo "https://$DOMAIN"

if [[ "$ENABLE_WS" =~ ^[Yy]$ ]]; then
echo "WebSocket Endpoint:"
echo "wss://ws.$DOMAIN"
fi