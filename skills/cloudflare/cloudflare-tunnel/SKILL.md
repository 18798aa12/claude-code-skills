---
name: cloudflare-tunnel
description: Set up cloudflared tunnels for exposing local services through Cloudflare. Covers WebSocket services, 4 common pitfalls with auto-fixes, and multi-service configuration on a single tunnel.
author: Jope Miler, Claude
version: 1.0.0
tags: [cloudflare, tunnel, cloudflared, websocket, reverse-proxy, zero-trust]
---

# Cloudflare Tunnel (cloudflared)

Set up cloudflared tunnels to securely expose local services (web apps, WebSocket services, APIs) through Cloudflare's network without opening ports on your firewall. Especially useful for WebSocket services that break under Cloudflare's Flexible SSL mode.

## When to use

- Expose a local/server service to the internet through Cloudflare
- WebSocket service (chat, file sharing, remote desktop) is unstable behind Cloudflare Flexible SSL
- Need to serve multiple services from one server under different subdomains
- Want zero-trust access without opening firewall ports
- Self-hosted services behind NAT/CGNAT

## Architecture

```
Internet Users
    │
    ↓  HTTPS (Cloudflare Edge)
    │
┌────────────────────────────────────────┐
│  Cloudflare Network                     │
│                                        │
│  app1.example.com ─┐                   │
│  app2.example.com ─┼─→ Tunnel Endpoint │
│  app3.example.com ─┘                   │
└────────────────┬───────────────────────┘
                 │  Encrypted tunnel
                 │  (outbound connection from your server)
┌────────────────▼───────────────────────┐
│  Your Server                            │
│                                        │
│  cloudflared (tunnel client)            │
│    │                                    │
│    ├─→ http://127.0.0.1:3000  (App 1)  │
│    ├─→ http://127.0.0.1:3001  (App 2)  │
│    └─→ http://127.0.0.1:8080  (App 3)  │
└────────────────────────────────────────┘
```

**Key advantage:** Your server makes an outbound connection to Cloudflare — no inbound ports needed.

## Auto-Setup Flow

### Step 1: Install cloudflared

```bash
# Debian/Ubuntu
curl -fsSL https://pkg.cloudflare.com/cloudflare-main.gpg | sudo tee /usr/share/keyrings/cloudflare-main.gpg >/dev/null
echo "deb [signed-by=/usr/share/keyrings/cloudflare-main.gpg] https://pkg.cloudflare.com/cloudflared $(lsb_release -cs) main" | \
  sudo tee /etc/apt/sources.list.d/cloudflared.list
sudo apt update && sudo apt install -y cloudflared

# Or direct binary
curl -fsSL https://github.com/cloudflare/cloudflared/releases/latest/download/cloudflared-linux-amd64 -o /usr/local/bin/cloudflared
chmod +x /usr/local/bin/cloudflared

# Verify
cloudflared version
```

### Step 2: Create Tunnel via API

```bash
# Required API token permissions:
# - Account.Cloudflare Tunnel: Edit
# - Zone.DNS: Edit
# - Zone.Zone: Read

# Generate a tunnel secret (base64-encoded 32 bytes)
TUNNEL_SECRET=$(openssl rand -base64 32)

# Create tunnel
TUNNEL_RESPONSE=$(curl -s -X POST \
  "https://api.cloudflare.com/client/v4/accounts/$ACCOUNT_ID/cfd_tunnel" \
  -H "Authorization: Bearer $API_TOKEN" \
  -H "Content-Type: application/json" \
  -d "{\"name\":\"my-tunnel\",\"tunnel_secret\":\"$TUNNEL_SECRET\",\"config_src\":\"local\"}")

TUNNEL_ID=$(echo "$TUNNEL_RESPONSE" | jq -r '.result.id')
echo "Tunnel ID: $TUNNEL_ID"
```

### Step 3: Write Credentials & Config

```bash
# Create credentials file
sudo mkdir -p /etc/cloudflared
cat > /tmp/tunnel-creds.json << EOF
{
  "AccountTag": "$ACCOUNT_ID",
  "TunnelSecret": "$TUNNEL_SECRET",
  "TunnelID": "$TUNNEL_ID"
}
EOF
sudo mv /tmp/tunnel-creds.json /etc/cloudflared/$TUNNEL_ID.json
sudo chmod 600 /etc/cloudflared/$TUNNEL_ID.json

# Create config
cat > /tmp/config.yml << EOF
tunnel: $TUNNEL_ID
credentials-file: /etc/cloudflared/$TUNNEL_ID.json

ingress:
  # Add your services here:
  - hostname: app1.example.com
    service: http://127.0.0.1:3000
  - hostname: app2.example.com
    service: http://127.0.0.1:8080
  # Catch-all (REQUIRED — must be last)
  - service: http_status:404
EOF
sudo mv /tmp/config.yml /etc/cloudflared/config.yml
```

### Step 4: Set Up DNS

```bash
# Create CNAME record pointing to tunnel
curl -X POST "https://api.cloudflare.com/client/v4/zones/$ZONE_ID/dns_records" \
  -H "Authorization: Bearer $API_TOKEN" \
  -H "Content-Type: application/json" \
  -d "{
    \"type\": \"CNAME\",
    \"name\": \"app1\",
    \"content\": \"$TUNNEL_ID.cfargotunnel.com\",
    \"proxied\": true
  }"
```

### Step 5: Install as System Service

```bash
# Install systemd service
sudo cloudflared --config /etc/cloudflared/config.yml service install

# Start and enable
sudo systemctl start cloudflared
sudo systemctl enable cloudflared

# Verify
sudo systemctl status cloudflared
curl -I https://app1.example.com
```

## The 4 Critical Pitfalls (WebSocket Services)

These pitfalls were discovered while deploying WebSocket-based services (file sharing, remote desktop, chat). Each one causes subtle failures that are hard to diagnose.

### Pitfall 1: `localhost` → IPv6/IPv4 Mismatch

**Symptom:**
```
ERR error="read tcp [::1]:51408->[::1]:3002: read: connection reset by peer"
```

**Cause:** cloudflared resolves `localhost` to IPv6 `[::1]` first, but Docker containers with `-p 3002:3000` only bind IPv4 `0.0.0.0:3002`.

**Fix:** Always use `127.0.0.1` instead of `localhost` in ingress rules:
```yaml
# ❌ WRONG
ingress:
  - hostname: app.example.com
    service: http://localhost:3000

# ✅ CORRECT
ingress:
  - hostname: app.example.com
    service: http://127.0.0.1:3000
```

### Pitfall 2: WebSocket Backend Can't Read Real Client IP

**Symptom:** All clients appear as the same IP (127.0.0.1). Services that group by IP (file sharing rooms, chat rooms) put everyone in the same group or no group.

**Cause:** The app reads the direct connection IP (cloudflared → app = 127.0.0.1) instead of the forwarded headers.

**Fix:** Enable proxy trust in your application:
```bash
# For Node.js/Express apps:
# Set trust proxy or equivalent environment variable
# Many apps use: WS_BEHIND_PROXY=true or TRUST_PROXY=true

# Docker example:
docker run -d \
  -e WS_BEHIND_PROXY=true \
  -p 3000:3000 \
  my-websocket-app

# The app should then read:
# X-Forwarded-For or CF-Connecting-IP headers
```

### Pitfall 3: IPv6 Localization (Same LAN, Different IPs)

**Symptom:** Devices on the same WiFi network appear in different rooms/groups. They each have a unique IPv6 Global Unicast Address.

**Cause:** Each device on the same WiFi gets its own IPv6 GUA. Services that group by exact IP see them as different users.

**Fix:** Configure the app to group by /64 prefix instead of exact IP:
```bash
# If the app supports it (e.g., IPV6_LOCALIZE setting):
docker run -d \
  -e IPV6_LOCALIZE=4 \
  my-app

# Value 4 means: group by first 4 segments of IPv6 (/64 prefix)
# So 2001:db8:1234:5678::1 and 2001:db8:1234:5678::2 → same group
# Valid range: 1-7 (NOT 64 — it's the number of segments, not CIDR bits)
```

### Pitfall 4: WebRTC Not Using LAN Direct Connection

**Symptom:** WebRTC-based apps (file sharing, video calls) transfer data through external servers even when both devices are on the same LAN. Slow speeds.

**Cause:** Chrome's `enable-webrtc-hide-local-ips-with-mdns` flag (enabled by default) replaces local IPs with `xxx.local` mDNS names. WebRTC ICE can't discover LAN peers.

**Fix (client-side — cannot be fixed server-side):**
```
1. Open chrome://flags/#enable-webrtc-hide-local-ips-with-mdns
2. Set to "Disabled"
3. Relaunch Chrome
```

**Note:** This is a client-side browser setting. You cannot fix this from the server. Document it for your users.

## Adding Services to an Existing Tunnel

One tunnel can serve multiple hostnames. To add a new service:

```bash
# 1. Edit config
sudo nano /etc/cloudflared/config.yml
# Add new ingress rule BEFORE the catch-all:
#   - hostname: newapp.example.com
#     service: http://127.0.0.1:NEW_PORT

# 2. Add DNS record
curl -X POST "https://api.cloudflare.com/client/v4/zones/$ZONE_ID/dns_records" \
  -H "Authorization: Bearer $API_TOKEN" \
  -H "Content-Type: application/json" \
  -d '{
    "type": "CNAME",
    "name": "newapp",
    "content": "'$TUNNEL_ID'.cfargotunnel.com",
    "proxied": true
  }'

# 3. Restart cloudflared
sudo systemctl restart cloudflared

# 4. Verify
curl -I https://newapp.example.com
```

## Auto-Fix: Common Issues

### Tunnel Not Starting

```bash
# Check logs
sudo journalctl -u cloudflared -n 50 --no-pager

# Common causes:
# 1. Invalid credentials file
sudo cat /etc/cloudflared/*.json | jq .
# Must have AccountTag, TunnelSecret, TunnelID

# 2. Config syntax error
cloudflared tunnel --config /etc/cloudflared/config.yml validate

# 3. Missing catch-all ingress rule
# Last ingress rule MUST be: - service: http_status:404
```

### 502 Bad Gateway

```bash
# Symptom: Tunnel works but returns 502
# Cause: Backend service is not running or wrong port

# Check if backend is listening
ss -tlnp | grep :3000

# If not running, start it:
docker ps -a  # check if container stopped
docker start my-container

# If running but wrong port, update config:
sudo sed -i 's|127.0.0.1:WRONG_PORT|127.0.0.1:CORRECT_PORT|' /etc/cloudflared/config.yml
sudo systemctl restart cloudflared
```

### Connection Reset / Timeout

```bash
# Symptom: Intermittent connection resets
# Cause: Usually IPv6/IPv4 mismatch (Pitfall 1)

# Check which IP cloudflared is connecting to:
sudo journalctl -u cloudflared | grep -i "connect"

# Fix: Change localhost → 127.0.0.1 in config
sudo sed -i 's|localhost:|127.0.0.1:|g' /etc/cloudflared/config.yml
sudo systemctl restart cloudflared
```

### WebSocket Disconnecting

```bash
# Symptom: WebSocket connects but drops after ~100 seconds
# Cause: Cloudflare's default WebSocket idle timeout

# Fix 1: Enable WebSocket keep-alive in your app
# Most WebSocket libraries support ping/pong frames

# Fix 2: If using Flexible SSL mode and WS keeps dropping,
# migrate to cloudflared tunnel (this is the whole point of this skill)

# Verify tunnel is handling WebSocket:
sudo journalctl -u cloudflared | grep -i "websocket"
```

### DNS Record Conflict

```bash
# Symptom: "DNS record already exists"
# Cause: Old A record for the same hostname

# Fix: Delete old record first, then create CNAME
# List records
curl -s "https://api.cloudflare.com/client/v4/zones/$ZONE_ID/dns_records?name=app.example.com" \
  -H "Authorization: Bearer $API_TOKEN" | jq '.result[] | {id, type, name, content}'

# Delete old record
curl -X DELETE "https://api.cloudflare.com/client/v4/zones/$ZONE_ID/dns_records/$RECORD_ID" \
  -H "Authorization: Bearer $API_TOKEN"

# Create new CNAME
# (same as Step 4 above)
```

## Docker Service Example

Complete example deploying a WebSocket-based file sharing service behind cloudflared:

```bash
# 1. Run the service
docker run -d --name=myapp --restart=always \
  -p 3000:3000 \
  -e PUID=1000 -e PGID=1000 \
  -e WS_BEHIND_PROXY=true \
  -e IPV6_LOCALIZE=4 \
  -e RATE_LIMIT=false \
  my-websocket-app:latest

# 2. Add to cloudflared config (use 127.0.0.1, NOT localhost!)
# Edit /etc/cloudflared/config.yml:
#   - hostname: myapp.example.com
#     service: http://127.0.0.1:3000

# 3. Add DNS
# CNAME: myapp → $TUNNEL_ID.cfargotunnel.com

# 4. Restart tunnel
sudo systemctl restart cloudflared

# 5. Test
curl -I https://myapp.example.com
# Should return 200
```

## Useful Commands

```bash
# List tunnels
cloudflared tunnel list

# Show tunnel info
cloudflared tunnel info $TUNNEL_ID

# Validate config
cloudflared tunnel --config /etc/cloudflared/config.yml validate

# Run tunnel (foreground, for debugging)
cloudflared tunnel --config /etc/cloudflared/config.yml run

# Check service status
sudo systemctl status cloudflared

# View logs
sudo journalctl -u cloudflared -f

# Delete a tunnel (stops all connections)
cloudflared tunnel delete $TUNNEL_ID
```

## API Token Permissions

The minimum API token permissions needed:

| Permission | Scope | Purpose |
|-----------|-------|---------|
| Account.Cloudflare Tunnel: Edit | Account | Create/manage tunnels |
| Zone.DNS: Edit | Zone | Create CNAME records |
| Zone.Zone: Read | Zone | List zones for DNS |
