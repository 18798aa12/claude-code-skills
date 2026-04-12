---
name: tailscale-mesh
description: Tailscale mesh networking setup — device joining, exit node configuration, SSH access across Windows/macOS/Linux
author: Zhou Qishun, Claude
version: 1.0.0
tags: [tailscale, vpn, mesh, networking, exit-node, ssh, cross-platform]
---

# Tailscale Mesh Networking

Set up and manage Tailscale mesh networks: join devices, configure exit nodes, enable SSH access across Windows, macOS, and Linux.

## When to use

- Setting up a new device in a Tailscale network
- Configuring a server as an exit node (route traffic through it)
- Enabling SSH access between devices via Tailscale
- Troubleshooting Tailscale connectivity issues
- Need to access a device behind NAT/firewall

## Installation

### Linux (Ubuntu/Debian)
```bash
curl -fsSL https://tailscale.com/install.sh | sh
sudo tailscale up --authkey=tskey-auth-xxxxx  # Or interactive login
```

### Linux (CentOS/RHEL)
```bash
curl -fsSL https://tailscale.com/install.sh | sh
sudo systemctl enable --now tailscaled
sudo tailscale up
```

### macOS
```bash
brew install tailscale
# Or download from https://tailscale.com/download/mac
```

### Windows
```powershell
# Download from https://tailscale.com/download/windows
# Or via winget:
winget install Tailscale.Tailscale
```

## Core Commands

### Device Management

```bash
# Join the network
sudo tailscale up

# Join with auth key (headless/automated)
sudo tailscale up --authkey=tskey-auth-xxxxx

# Check status
tailscale status

# See detailed info about this device
tailscale ip       # Show Tailscale IPs
tailscale netcheck # Network connectivity check

# Disconnect (keep installed)
sudo tailscale down

# Logout completely
sudo tailscale logout
```

### Exit Node Configuration

An exit node routes ALL internet traffic from other devices through itself. Useful when a device has restricted internet but can reach another device via Tailscale.

#### Advertise as Exit Node (Server Side)

```bash
# Linux: Enable IP forwarding first
echo 'net.ipv4.ip_forward = 1' | sudo tee -a /etc/sysctl.d/99-tailscale.conf
echo 'net.ipv6.conf.all.forwarding = 1' | sudo tee -a /etc/sysctl.d/99-tailscale.conf
sudo sysctl -p /etc/sysctl.d/99-tailscale.conf

# Advertise this device as an exit node
sudo tailscale up --advertise-exit-node

# Also advertise as subnet router (optional, for LAN access)
sudo tailscale up --advertise-exit-node --advertise-routes=192.168.1.0/24
```

Then approve the exit node in the [Tailscale admin console](https://login.tailscale.com/admin/machines).

#### Use an Exit Node (Client Side)

```bash
# List available exit nodes
tailscale status | grep "exit node"

# Use a specific exit node
sudo tailscale set --exit-node=<IP_OR_HOSTNAME>

# Keep LAN access while using exit node (IMPORTANT for SSH!)
sudo tailscale set --exit-node=<IP> --exit-node-allow-lan-access=true

# Stop using exit node
sudo tailscale set --exit-node=
```

**WARNING**: Setting an exit node may break existing SSH connections if `--exit-node-allow-lan-access` is not enabled.

### SSH via Tailscale

#### Linux/macOS: Native Tailscale SSH

```bash
# Enable Tailscale SSH on the server (replaces OpenSSH for Tailscale connections)
sudo tailscale up --ssh

# Connect from another device
ssh user@<tailscale-hostname>
# Example: ssh zqs@l40
```

#### Windows: Cannot use Tailscale SSH directly

Windows does not support Tailscale SSH as a server. Workarounds:

**Option 1: Use OpenSSH (Recommended)**
```powershell
# Windows has built-in OpenSSH server
# Enable via Settings > Apps > Optional Features > OpenSSH Server
# Or via PowerShell (Admin):
Add-WindowsCapability -Online -Name OpenSSH.Server~~~~0.0.1.0
Start-Service sshd
Set-Service -Name sshd -StartupType 'Automatic'

# Now other Tailscale devices can SSH to this Windows machine
# using the Tailscale IP:
ssh user@100.x.x.x
```

**Option 2: Use Tailscale IP with regular SSH**
```bash
# From any device, SSH to Windows using its Tailscale IP
ssh windowsuser@100.108.97.45
```

**Option 3: Use Windows as a jumpbox**
```bash
# SSH through Windows to reach another device
ssh -J windowsuser@100.108.97.45 linuxuser@100.100.203.100
```

## Network Topology Examples

### Scenario 1: GPU Server Behind Firewall

```
┌─────────────┐    Tailscale    ┌─────────────┐
│ Your Laptop │◄──────────────►│  GPU Server  │
│ (Windows)   │   100.x.x.x    │  (Linux)     │
│             │                 │  No internet │
└─────────────┘                 └─────────────┘
       │
       │ Exit Node
       ▼
┌─────────────┐
│  VPS (HK)   │──── Internet ──── huggingface.co
│ Exit Node   │
└─────────────┘
```

```bash
# On GPU server: use VPS as exit node to access internet
sudo tailscale set --exit-node=100.127.35.1 --exit-node-allow-lan-access=true

# Download model via the exit node's internet
wget https://huggingface.co/...
```

### Scenario 2: Multi-Machine Mesh

```
┌──────────┐     ┌──────────┐     ┌──────────┐
│  Laptop  │◄───►│  Desktop │◄───►│ GPU Srv  │
│ Win/Mac  │     │ Windows  │     │  Linux   │
│ .97.45   │     │ .108.97  │     │ .203.100 │
└──────────┘     └──────────┘     └──────────┘
      │               │                │
      └───────────────┼────────────────┘
                      │
               ┌──────────┐
               │  VPS x14 │  (Exit Nodes)
               │ HK/JP/US │
               └──────────┘
```

## Troubleshooting

| Issue | Command | Solution |
|-------|---------|----------|
| Can't reach device | `tailscale ping <ip>` | Check if device is online in admin console |
| Slow connection (relay) | `tailscale status` (shows "relay") | `tailscale netcheck` to diagnose; may need to open UDP port 41641 |
| Exit node not working | `curl ifconfig.me` | Approve exit node in admin console; check IP forwarding |
| SSH timeout via Tailscale | `tailscale ping <ip>` | Use `--exit-node-allow-lan-access=true` |
| Device shows offline | `sudo systemctl status tailscaled` | Restart: `sudo systemctl restart tailscaled` |
| "relay hkg" instead of direct | Check firewall | Open UDP 41641 on both sides for direct connection |

## Security Best Practices

- Use ACLs in Tailscale admin console to restrict which devices can access what
- Enable MFA on your Tailscale account
- Use `--exit-node-allow-lan-access=true` carefully (allows LAN access from exit node)
- Regularly review connected devices in admin console
- Use auth keys with expiration for automated setups
