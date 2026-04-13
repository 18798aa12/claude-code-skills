---
name: vps-singbox
description: Deploy sing-box proxy server on VPS with 5 protocols (VLESS Reality, Hysteria2, TUIC, Trojan WS, Trojan CDN). Covers multi-node management, Tailscale mesh, monitoring, and troubleshooting from 13-node production experience.
author: Jope Miler, Claude
version: 1.0.0
tags: [vps, sing-box, proxy, vless, reality, hysteria2, tuic, trojan, tailscale, server]
---

# VPS sing-box Multi-Protocol Proxy Server

Deploy a production-ready proxy server on VPS using sing-box with 5 protocols. Covers initial server hardening, protocol configuration, CDN relay, Tailscale mesh networking, monitoring, and automated troubleshooting. Based on real experience managing 13 production nodes across 8 countries.

## When to use

- Setting up a new VPS as a proxy server
- Adding protocols (VLESS, Hysteria2, TUIC, Trojan) to an existing server
- Configuring Cloudflare CDN relay for Trojan+WS
- Building a Tailscale mesh between multiple VPS nodes
- Troubleshooting connection issues with specific protocols
- Hardening a VPS for long-term proxy use

## Protocol Overview

| Protocol | Port | Transport | Anti-Detection | CDN Relay | Speed |
|----------|------|-----------|---------------|-----------|-------|
| VLESS Reality | 443 | TCP+TLS (XTLS) | Excellent (mimics real TLS) | ❌ | ★★★★★ |
| Hysteria2 | 8443 | QUIC/UDP | Good | ❌ | ★★★★★ |
| TUIC | 8388 | QUIC/UDP | Good | ❌ | ★★★★ |
| Trojan+WS+TLS | 57712 | WebSocket+TLS | Very Good | ❌ (direct) | ★★★★ |
| Trojan+WS+TLS (CDN) | 2053 | WebSocket+TLS | Excellent (via CF) | ✅ | ★★★ |

**Recommended combo:** VLESS Reality (primary) + Hysteria2 (UDP-optimized) + Trojan CDN (anti-blocking fallback)

## Step 1: Server Hardening

### SSH Security

```bash
# Change SSH port (avoid common scanning)
sudo sed -i 's/#Port 22/Port 2233/' /etc/ssh/sshd_config

# Disable password auth (key only)
sudo sed -i 's/#PasswordAuthentication yes/PasswordAuthentication no/' /etc/ssh/sshd_config
sudo sed -i 's/PasswordAuthentication yes/PasswordAuthentication no/' /etc/ssh/sshd_config

# Restart SSH
sudo systemctl restart sshd

# Deploy SSH key (from local machine)
ssh-copy-id -i ~/.ssh/id_ed25519.pub -p 2233 user@server-ip
```

### Firewall Setup

```bash
# Install UFW
sudo apt install -y ufw

# Default deny incoming
sudo ufw default deny incoming
sudo ufw default allow outgoing

# Allow SSH (new port)
sudo ufw allow 2233/tcp

# Allow proxy protocols
sudo ufw allow 443/tcp     # VLESS Reality
sudo ufw allow 8443/udp    # Hysteria2
sudo ufw allow 8388/udp    # TUIC
sudo ufw allow 57712/tcp   # Trojan direct
sudo ufw allow 2053/tcp    # Trojan CDN

# Allow monitoring
sudo ufw allow 45876/tcp   # Beszel agent (optional)

# Enable
sudo ufw enable
sudo ufw status
```

### Enable BBR

```bash
# Check if BBR is available
sysctl net.ipv4.tcp_available_congestion_control

# Enable BBR
echo "net.core.default_qdisc=fq" | sudo tee -a /etc/sysctl.conf
echo "net.ipv4.tcp_congestion_control=bbr" | sudo tee -a /etc/sysctl.conf
sudo sysctl -p

# Verify
sysctl net.ipv4.tcp_congestion_control
# Should output: net.ipv4.tcp_congestion_control = bbr
```

## Step 2: Install sing-box

```bash
# Install latest stable
bash <(curl -fsSL https://sing-box.app/deb-install.sh)

# Or manual install
SINGBOX_VERSION="1.13.5"
curl -fsSL "https://github.com/SagerNet/sing-box/releases/download/v${SINGBOX_VERSION}/sing-box-${SINGBOX_VERSION}-linux-amd64.tar.gz" | \
  sudo tar xz -C /usr/local/bin --strip-components=1 sing-box-${SINGBOX_VERSION}-linux-amd64/sing-box

# Verify
sing-box version
```

## Step 3: Generate Keys & Certificates

### VLESS Reality Keys

```bash
# Generate Reality key pair
sing-box generate reality-keypair
# Output:
# PrivateKey: <PRIVATE_KEY>
# PublicKey:  <PUBLIC_KEY>

# Generate short ID
openssl rand -hex 8
# Output: <SHORT_ID>

# Generate UUID
sing-box generate uuid
# Output: <UUID>
```

### Self-Signed Certificate (for Hysteria2/TUIC/Trojan)

```bash
# Generate self-signed cert
sudo mkdir -p /etc/sing-box/certs
sudo openssl req -x509 -nodes -newkey ec:<(openssl ecparam -name prime256v1) \
  -keyout /etc/sing-box/certs/server.key \
  -out /etc/sing-box/certs/server.crt \
  -subj "/CN=example.com" -days 3650

sudo chmod 644 /etc/sing-box/certs/server.crt
sudo chmod 600 /etc/sing-box/certs/server.key
```

## Step 4: sing-box Configuration

```json
{
  "log": {
    "level": "warn",
    "timestamp": true
  },
  "dns": {
    "servers": [
      {
        "tag": "cloudflare",
        "address": "1.1.1.1"
      }
    ]
  },
  "inbounds": [
    {
      "type": "vless",
      "tag": "vless-reality",
      "listen": "::",
      "listen_port": 443,
      "users": [
        {
          "uuid": "<YOUR_UUID>",
          "flow": "xtls-rprx-vision"
        }
      ],
      "tls": {
        "enabled": true,
        "server_name": "www.microsoft.com",
        "reality": {
          "enabled": true,
          "handshake": {
            "server": "www.microsoft.com",
            "server_port": 443
          },
          "private_key": "<REALITY_PRIVATE_KEY>",
          "short_id": ["<SHORT_ID>"]
        }
      }
    },
    {
      "type": "hysteria2",
      "tag": "hysteria2",
      "listen": "::",
      "listen_port": 8443,
      "users": [
        {
          "password": "<HY2_PASSWORD>"
        }
      ],
      "tls": {
        "enabled": true,
        "certificate_path": "/etc/sing-box/certs/server.crt",
        "key_path": "/etc/sing-box/certs/server.key"
      }
    },
    {
      "type": "tuic",
      "tag": "tuic",
      "listen": "::",
      "listen_port": 8388,
      "users": [
        {
          "uuid": "<YOUR_UUID>",
          "password": "<TUIC_PASSWORD>"
        }
      ],
      "congestion_control": "bbr",
      "tls": {
        "enabled": true,
        "alpn": ["h3"],
        "certificate_path": "/etc/sing-box/certs/server.crt",
        "key_path": "/etc/sing-box/certs/server.key"
      }
    },
    {
      "type": "trojan",
      "tag": "trojan-ws-direct",
      "listen": "::",
      "listen_port": 57712,
      "users": [
        {
          "password": "<TROJAN_PASSWORD>"
        }
      ],
      "transport": {
        "type": "ws",
        "path": "/trojan-ws"
      },
      "tls": {
        "enabled": true,
        "certificate_path": "/etc/sing-box/certs/server.crt",
        "key_path": "/etc/sing-box/certs/server.key"
      }
    },
    {
      "type": "trojan",
      "tag": "trojan-ws-cdn",
      "listen": "::",
      "listen_port": 2053,
      "users": [
        {
          "password": "<TROJAN_PASSWORD>"
        }
      ],
      "transport": {
        "type": "ws",
        "path": "/trojan-cdn"
      },
      "tls": {
        "enabled": true,
        "certificate_path": "/etc/sing-box/certs/server.crt",
        "key_path": "/etc/sing-box/certs/server.key"
      }
    }
  ],
  "outbounds": [
    {
      "type": "direct",
      "tag": "direct"
    }
  ]
}
```

### Save and Start

```bash
# Write config
sudo nano /etc/sing-box/config.json

# Validate config
sing-box check -c /etc/sing-box/config.json

# Start service
sudo systemctl enable sing-box
sudo systemctl start sing-box
sudo systemctl status sing-box

# View logs
sudo journalctl -u sing-box -f
```

## Step 5: Cloudflare CDN Relay (Trojan)

For the CDN-relayed Trojan, set up a Cloudflare DNS record:

```bash
# Create DNS record pointing to your VPS
# Type: A, Name: node1, Content: YOUR_VPS_IP, Proxied: ON
curl -X POST "https://api.cloudflare.com/client/v4/zones/$ZONE_ID/dns_records" \
  -H "Authorization: Bearer $API_TOKEN" \
  -H "Content-Type: application/json" \
  -d '{
    "type": "A",
    "name": "node1",
    "content": "YOUR_VPS_IP",
    "proxied": true
  }'

# Client connects to: node1.example.com:2053
# Traffic flow: Client → CF CDN → Your VPS:2053
# CF free plan supports these TLS ports: 443, 2053, 2083, 2087, 2096, 8443
```

**Benefit:** Even if your VPS IP is blocked, the CDN relay still works because traffic goes through Cloudflare's IP range.

## Step 6: Tailscale Mesh (Optional)

Connect all VPS nodes into a mesh network for management:

```bash
# Install Tailscale
curl -fsSL https://tailscale.com/install.sh | sh

# Join network (disable Tailscale DNS to avoid conflicts)
sudo tailscale up --accept-dns=false --hostname=us-node1

# Verify
tailscale status

# Now you can SSH between nodes via Tailscale IPs:
ssh user@100.x.x.x -p 2233
```

## Step 7: Monitoring (Optional)

### Beszel Agent

```bash
# Install Beszel agent for resource monitoring
curl -fsSL https://raw.githubusercontent.com/henrygd/beszel/main/supplemental/scripts/install-agent.sh | bash

# Configure agent
sudo nano /etc/beszel/agent.env
# PORT=45876
# KEY=<your-monitoring-hub-key>

# Start
sudo systemctl enable beszel-agent
sudo systemctl start beszel-agent
```

## Auto-Fix: Common Issues

### VLESS Reality — Connection Timeout

```bash
# Symptom: Client connects but times out
# Cause 1: Firewall blocking port 443

# Check
sudo ufw status | grep 443
ss -tlnp | grep 443

# Fix: Open port
sudo ufw allow 443/tcp

# Cause 2: Wrong SNI server
# Reality handshake server must be reachable from VPS
curl -sI https://www.microsoft.com | head -3
# If blocked, try: www.apple.com, www.yahoo.com, dl.google.com
```

### Hysteria2 — "no route to host"

```bash
# Symptom: UDP connection fails
# Cause: Cloud provider blocks UDP or firewall not allowing UDP

# Check if UDP is allowed
sudo ufw status | grep 8443
# Must show 8443/udp ALLOW

# Some providers (e.g., Oracle Cloud) need Security List changes:
# Oracle Cloud Console → Networking → VCN → Security Lists → Ingress Rules
# Add: Source 0.0.0.0/0, UDP, Port 8443

# Test UDP from client:
nc -zu server-ip 8443
```

### TUIC — "ALPN mismatch"

```bash
# Symptom: TUIC connects but immediately drops
# Cause: ALPN mismatch between server and client

# Server config MUST have:
# "alpn": ["h3"]

# Client MUST also specify:
# alpn: h3

# Some clients (Surge) are lenient about ALPN, but Mihomo is strict
# Always explicitly set alpn on BOTH server and client
```

### Trojan CDN — "SSL handshake failed"

```bash
# Symptom: Connection through CDN fails with SSL error
# Cause: Using non-TLS port or wrong CF SSL mode

# CF free plan TLS ports: 443, 2053, 2083, 2087, 2096, 8443
# Make sure you're using one of these ports for CDN relay

# Also check: CF SSL mode should be "Full" (not "Flexible")
# Flexible = CF connects to origin via HTTP → breaks TLS
# Full = CF connects to origin via HTTPS → correct
```

### Cloud Provider Double Firewall

```bash
# Symptom: Ports open in UFW but still can't connect
# Cause: Cloud provider has its own firewall (AWS Security Groups, 
#         Oracle Security Lists, Alibaba Cloud Security Groups)

# Fix: Open ports in BOTH:
# 1. OS firewall (UFW) — sudo ufw allow PORT
# 2. Cloud console firewall — add ingress rule

# Common providers with double firewall:
# - AWS: Security Groups
# - Oracle Cloud: VCN Security Lists
# - Alibaba Cloud: Security Groups + Cloud Shield
# - Google Cloud: VPC Firewall Rules
```

### Alibaba Cloud Specific Issues

```bash
# Issue 1: Cloud Shield blocks SSH port 22
# Symptom: SSH works from some IPs but not others
# Cause: Alibaba's DDoS protection flags frequent SSH attempts
# Fix: Change SSH to non-standard port (e.g., 2233)

# Issue 2: chattr +i not supported on some VPS
# Symptom: "Operation not supported" when protecting resolv.conf
# Fix: Use systemd-resolved or manual DNS config instead

# Issue 3: First SSH requires jump host
# If you can't SSH directly from your local machine:
ssh -J user@jump-host:2233 user@alibaba-vps:2233
```

### sing-box Won't Start

```bash
# Check config syntax
sing-box check -c /etc/sing-box/config.json

# Common errors:
# 1. Duplicate port — two inbounds on same port
# 2. Invalid UUID — must be valid UUID v4
# 3. Certificate not found — check path exists
# 4. Permission denied on cert — chmod 644/600

# View detailed error
sudo journalctl -u sing-box -n 20 --no-pager
```

### Node IP Blocked

```bash
# Symptom: Can't connect to any protocol on the VPS
# Cause: IP blocked by GFW or ISP

# Test: Can you access non-proxy services?
curl -sI https://example.com  # From VPS itself — should work

# From local machine:
ping server-ip  # If timeout → IP likely blocked
curl --connect-timeout 5 https://server-ip:443  # If timeout → blocked

# Fix options:
# 1. Use CDN relay (Trojan CDN port 2053) — works even if IP is blocked
# 2. Get a new IP from your VPS provider
# 3. Use Cloudflare WARP as exit on the VPS
```

## Multi-Node Management

### Batch Deploy Script

```bash
#!/bin/bash
# Deploy sing-box config to multiple nodes

NODES=(
    "user@node1-ip:2233"
    "user@node2-ip:2233"
    "user@node3-ip:2233"
)

for node in "${NODES[@]}"; do
    echo "Deploying to $node..."
    scp -P ${node##*:} config.json ${node%:*}:/tmp/sing-box-config.json
    ssh -p ${node##*:} ${node%:*} "
        sudo cp /tmp/sing-box-config.json /etc/sing-box/config.json
        sudo sing-box check -c /etc/sing-box/config.json && \
        sudo systemctl restart sing-box && \
        echo 'OK: $(hostname)' || echo 'FAIL: $(hostname)'
    "
done
```

### Health Check Script

```bash
#!/bin/bash
# Check all nodes are responding

NODES=(
    "node1-ip:443"
    "node2-ip:443"
    "node3-ip:443"
)

for node in "${NODES[@]}"; do
    IP=${node%:*}
    PORT=${node##*:}
    if timeout 5 bash -c "echo > /dev/tcp/$IP/$PORT" 2>/dev/null; then
        echo "✓ $IP:$PORT — OK"
    else
        echo "✗ $IP:$PORT — UNREACHABLE"
    fi
done
```

## Client Configuration Reference

### Quantumult X

```ini
# VLESS Reality
vless=server-ip:443, method=none, password=<UUID>, obfs=over-tls, obfs-host=www.microsoft.com, tls-verification=false, fast-open=false, udp-relay=false, tag=US-VLESS

# Trojan CDN
trojan=node1.example.com:2053, password=<PASSWORD>, obfs=wss, obfs-host=node1.example.com, obfs-uri=/trojan-cdn, tls-verification=false, fast-open=false, udp-relay=false, tag=US-Trojan-CDN
```

### Surge

```ini
# VLESS Reality (requires Surge 5.8+)
US-VLESS = vless, server-ip, 443, username=<UUID>, tls=true, sni=www.microsoft.com, reality=true, reality-public-key=<PUBLIC_KEY>, reality-short-id=<SHORT_ID>

# Hysteria2
US-HY2 = hysteria2, server-ip, 8443, password=<PASSWORD>, skip-cert-verify=true

# TUIC
US-TUIC = tuic, server-ip, 8388, token=<UUID>:<PASSWORD>, alpn=h3, skip-cert-verify=true
```

### Clash/Mihomo

```yaml
proxies:
  - name: US-VLESS
    type: vless
    server: server-ip
    port: 443
    uuid: <UUID>
    flow: xtls-rprx-vision
    tls: true
    servername: www.microsoft.com
    reality-opts:
      public-key: <PUBLIC_KEY>
      short-id: <SHORT_ID>

  - name: US-HY2
    type: hysteria2
    server: server-ip
    port: 8443
    password: <PASSWORD>
    skip-cert-verify: true

  - name: US-TUIC
    type: tuic
    server: server-ip
    port: 8388
    uuid: <UUID>
    password: <PASSWORD>
    alpn: [h3]
    skip-cert-verify: true
```
