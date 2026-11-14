# Hoodium Mainchain EVM RPC Setup
sudo bash evm-rpc-setup.sh

git clone https://github.com/hoodium-io/evm-rpc-script

However, for a production server I'd recommend creating a dedicated folder:

chmod +x rpc-setup.sh

sudo ./rpc-setup.sh


A couple of important notes before running it:

1. DNS Must Already Point to the VPS

Your domain should already have an A record:

rpc.example.com  -> VPS_PUBLIC_IP


Verify:

dig rpc.example.com +short

or

nslookup rpc.example.com


The returned IP should match your VPS public IP.

2. Run as sudo

The script modifies:

/etc/nginx/
/etc/letsencrypt/
/etc/systemd/
/etc/ssl/


so it must run with elevated privileges:

sudo ./rpc-setup.sh

3. If the RPC Node Runs on the Same VPS

Use:

Backend RPC IP: 127.0.0.1
RPC Port: 8545


This is actually the preferred setup because the node is never exposed directly to the internet.

Example architecture:

Internet
    ↓
https://rpc.mydomain.com
    ↓
NGINX + SSL
    ↓
127.0.0.1:8545
    ↓
geth / reth / runed

4. If the Node Is on Another Server

Use the node's public IP:

Backend RPC IP: 44.xx.xx.xx
RPC Port: 8545

Recommended Production Layout

I would keep it like this:

/evm-rpc-script/
├── rpc-setup.sh
├── backups/
├── nginx-templates/
├── logs/
└── configs/


Then run:

cd evm-rpc-script
sudo ./rpc-setup.sh
