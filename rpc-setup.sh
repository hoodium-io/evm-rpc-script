#!/bin/bash

set -e

GREEN="\033[0;32m"
RED="\033[0;31m"
YELLOW="\033[1;33m"
NC="\033[0m"

echo ""
echo "=========================================="
echo " Hoodium Mainchain Devnet"
echo " EVM RPC Gateway Installer"
echo "=========================================="
echo ""

###################################
# DOMAIN SETUP
###################################

read -p "Base Domain (example: hoodium.dev): " BASE_DOMAIN

if [ -z "$BASE_DOMAIN" ]; then
    echo -e "${RED}Base domain cannot be empty.${NC}"
    exit 1
fi

read -p "RPC Subdomain [rpc]: " RPC_SUBDOMAIN
RPC_SUBDOMAIN=${RPC_SUBDOMAIN:-rpc}

RPC_DOMAIN="${RPC_SUBDOMAIN}.${BASE_DOMAIN}"

read -p "Admin Email: " EMAIL

###################################
# BACKEND
###################################

read -p "Backend RPC IP [127.0.0.1]: " RPC_IP
RPC_IP=${RPC_IP:-127.0.0.1}

read -p "Backend RPC Port [8545]: " RPC_PORT
RPC_PORT=${RPC_PORT:-8545}

###################################
# WEBSOCKET
###################################

read -p "Enable WebSocket? (y/n): " ENABLE_WS

if [[ "$ENABLE_WS" =~ ^[Yy]$ ]]; then

    read -p "WS Subdomain [ws]: " WS_SUBDOMAIN
    WS_SUBDOMAIN=${WS_SUBDOMAIN:-ws}

    WS_DOMAIN="${WS_SUBDOMAIN}.${BASE_DOMAIN}"

    read -p "WebSocket Port [8546]: " WS_PORT
    WS_PORT=${WS_PORT:-8546}

fi

###################################
# OPTIONS
###################################

read -p "Enable SSL? (y/n): " ENABLE_SSL
read -p "Enable Authentication? (y/n): " ENABLE_AUTH
read -p "Enable Rate Limiting? (y/n): " ENABLE_RATE
read -p "Enable DDoS Protection? (y/n): " ENABLE_DDOS
read -p "Enable Load Balancing? (y/n): " ENABLE_LB

###################################
# LOAD BALANCER
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
# AUTH
###################################

if [[ "$ENABLE_AUTH" =~ ^[Yy]$ ]]; then

    read -p "Username: " RPC_USER
    read -s -p "Password: " RPC_PASS
    echo ""

fi

###################################
# RATE LIMIT
###################################

if [[ "$ENABLE_RATE" =~ ^[Yy]$ ]]; then

    read -p "Requests per second [30]: " RATE
    RATE=${RATE:-30}

fi

###################################
# INSTALL
###################################

echo ""
echo "Installing packages..."

apt update

apt install -y \
nginx \
certbot \
python3-certbot-nginx \
apache2-utils \
curl \
dnsutils

###################################
# FIREWALL
###################################

if command -v ufw > /dev/null 2>&1; then

    ufw allow 80/tcp
    ufw allow 443/tcp

fi

###################################
# DNS VALIDATION
###################################

SERVER_IP=$(curl -4 -s ifconfig.me)

echo ""
echo "Checking DNS..."
echo ""

RPC_DNS_IP=$(dig +short "$RPC_DOMAIN" | tail -n1)

echo "Server IP : $SERVER_IP"
echo "RPC DNS   : $RPC_DNS_IP"

if [ "$RPC_DNS_IP" != "$SERVER_IP" ]; then

    echo ""
    echo -e "${RED}ERROR:${NC}"
    echo "$RPC_DOMAIN is not pointing to this VPS."
    exit 1

fi

if [[ "$ENABLE_WS" =~ ^[Yy]$ ]]; then

    WS_DNS_IP=$(dig +short "$WS_DOMAIN" | tail -n1)

    echo "WS DNS    : $WS_DNS_IP"

    if [ "$WS_DNS_IP" != "$SERVER_IP" ]; then

        echo ""
        echo -e "${RED}ERROR:${NC}"
        echo "$WS_DOMAIN is not pointing to this VPS."
        exit 1

    fi
fi

echo ""
echo -e "${GREEN}DNS Validation Passed${NC}"

###################################
# AUTH FILE
###################################

if [[ "$ENABLE_AUTH" =~ ^[Yy]$ ]]; then

    htpasswd -bc /etc/nginx/.rpc-auth \
    "$RPC_USER" \
    "$RPC_PASS"

fi

###################################
# TARGET
###################################

if [[ "$ENABLE_LB" =~ ^[Yy]$ ]]; then
    TARGET="http://rpc_cluster"
else
    TARGET="http://${RPC_IP}:${RPC_PORT}"
fi

###################################
# BUILD CONFIG
###################################

NGINX_CONF="/etc/nginx/sites-available/${BASE_DOMAIN}-rpc"

rm -f "$NGINX_CONF"

cat > "$NGINX_CONF" <<EOF
$UPSTREAM
EOF

###################################
# RATE LIMIT
###################################

if [[ "$ENABLE_RATE" =~ ^[Yy]$ ]]; then

cat >> "$NGINX_CONF" <<EOF

limit_req_zone \$binary_remote_addr zone=rpc_limit:10m rate=${RATE}r/s;

EOF

fi

###################################
# DDOS
###################################

if [[ "$ENABLE_DDOS" =~ ^[Yy]$ ]]; then

cat >> "$NGINX_CONF" <<EOF

limit_conn_zone \$binary_remote_addr zone=conn_limit:10m;

EOF

fi

###################################
# RPC SERVER
###################################

cat >> "$NGINX_CONF" <<EOF

server {

    listen 80;
    server_name $RPC_DOMAIN;

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
# DDOS
###################################

if [[ "$ENABLE_DDOS" =~ ^[Yy]$ ]]; then

cat >> "$NGINX_CONF" <<EOF
        limit_conn conn_limit 20;

EOF

fi

###################################
# PROXY
###################################

cat >> "$NGINX_CONF" <<EOF

        proxy_pass $TARGET;

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
# WS SERVER
###################################

if [[ "$ENABLE_WS" =~ ^[Yy]$ ]]; then

cat >> "$NGINX_CONF" <<EOF

server {

    listen 80;
    server_name $WS_DOMAIN;

    location / {

        proxy_pass http://${RPC_IP}:${WS_PORT};

        proxy_http_version 1.1;

        proxy_set_header Upgrade \$http_upgrade;
        proxy_set_header Connection "upgrade";

        proxy_set_header Host \$host;
        proxy_set_header X-Real-IP \$remote_addr;
        proxy_set_header X-Forwarded-For \$proxy_add_x_forwarded_for;

        proxy_read_timeout 86400;
    }

}
EOF

fi

###################################
# ENABLE SITE
###################################

ln -sf \
"$NGINX_CONF" \
"/etc/nginx/sites-enabled/${BASE_DOMAIN}-rpc"

rm -f /etc/nginx/sites-enabled/default

###################################
# TEST NGINX
###################################

nginx -t
systemctl restart nginx

###################################
# SSL
###################################

if [[ "$ENABLE_SSL" =~ ^[Yy]$ ]]; then

    echo ""
    echo "Requesting SSL certificates..."

    if [[ "$ENABLE_WS" =~ ^[Yy]$ ]]; then

        certbot \
        --nginx \
        -d "$RPC_DOMAIN" \
        -d "$WS_DOMAIN" \
        -m "$EMAIL" \
        --agree-tos \
        --non-interactive \
        --redirect

    else

        certbot \
        --nginx \
        -d "$RPC_DOMAIN" \
        -m "$EMAIL" \
        --agree-tos \
        --non-interactive \
        --redirect

    fi

fi

###################################
# RENEWAL TEST
###################################

certbot renew --dry-run || true

###################################
# COMPLETE
###################################

echo ""
echo -e "${GREEN}DeploymentEndpoint:"
echo "https://${RPC_DOMAIN}"

if [[ "$ENABLE_WS" =~ ^[Yy]$ ]]; then
    echo ""
    echo "WebSocket Endpoint:"
    echo "wss://${WS_DOMAIN}"
fi

echo ""
echo "Backend RPC:"
echo "${RPC_IP}:${RPC_PORT}"