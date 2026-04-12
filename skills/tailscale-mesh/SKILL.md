---
name: tailscale-mesh
description: Tailscale mesh networking — cross-platform SSH, exit nodes, device management. Auto-configures and fixes connectivity issues.
author: Jope Miler, Claude
version: 1.0.0
tags: [tailscale, vpn, mesh, networking, exit-node, ssh, cross-platform]
---

# Tailscale Mesh Networking

Set up and manage Tailscale mesh networks. Automatically configures cross-platform SSH access and exit nodes, and fixes common connectivity issues.

## When to use

- Setting up SSH access between devices on different networks
- A device needs internet access through another device (exit node)
- Connecting to a server behind NAT/firewall
- Need all your devices (Windows/macOS/Linux) to SSH to each other

## Auto-Setup Flow

### Install Tailscale (auto-detect platform)

```bash
# Linux (auto-detect distro)
if command -v apt &>/dev/null; then
    curl -fsSL https://tailscale.com/install.sh | sh
elif command -v yum &>/dev/null; then
    curl -fsSL https://tailscale.com/install.sh | sh
fi

# macOS
brew install tailscale

# Windows (PowerShell)
winget install Tailscale.Tailscale
```

### Join Network + Enable SSH

```bash
# Linux/macOS: join + enable Tailscale SSH
sudo tailscale up --ssh

# Windows: join (no --ssh support, use OpenSSH instead)
# GUI: sign in via system tray icon
# Then enable OpenSSH Server:
# Add-WindowsCapability -Online -Name OpenSSH.Server~~~~0.0.1.0
# Start-Service sshd
# Set-Service -Name sshd -StartupType 'Automatic'
```

### Auto-Fix: Windows SSH Access

Windows doesn't support `--ssh` flag. Claude should automatically:

```powershell
# 1. Check if OpenSSH Server is installed
Get-WindowsCapability -Online | Where-Object Name -like 'OpenSSH.Server*'

# 2. Install if missing
Add-WindowsCapability -Online -Name OpenSSH.Server~~~~0.0.1.0

# 3. Start and enable auto-start
Start-Service sshd
Set-Service -Name sshd -StartupType 'Automatic'

# 4. Verify
ssh localhost "echo Windows SSH OK"
```

## Cross-Platform SSH Matrix

After setup, all devices can SSH to each other:

```bash
# To Linux (Tailscale SSH or OpenSSH)
ssh user@100.x.x.x
ssh user@tailscale-hostname

# To macOS (Tailscale SSH)
ssh user@100.x.x.x

# To Windows (OpenSSH Server)
ssh windowsuser@100.x.x.x
```

## Exit Node Configuration

### Auto-Setup: Make Server an Exit Node

```bash
# 1. Enable IP forwarding (required)
echo 'net.ipv4.ip_forward = 1' | sudo tee -a /etc/sysctl.d/99-tailscale.conf
echo 'net.ipv6.conf.all.forwarding = 1' | sudo tee -a /etc/sysctl.d/99-tailscale.conf
sudo sysctl -p /etc/sysctl.d/99-tailscale.conf

# 2. Advertise as exit node
sudo tailscale up --advertise-exit-node

# 3. Remind user: approve in admin console
echo "IMPORTANT: Approve this exit node at https://login.tailscale.com/admin/machines"
```

### Auto-Setup: Use Exit Node (with safety)

```bash
# ALWAYS use --exit-node-allow-lan-access to prevent SSH disconnect!
sudo tailscale set --exit-node=EXIT_NODE_IP --exit-node-allow-lan-access=true

# Verify internet works
curl -s --connect-timeout 10 https://example.com -o /dev/null -w '%{http_code}'
# If 000 (failed), the exit node isn't working → revert:
# sudo tailscale set --exit-node=
```

### Auto-Fix: Exit Node Breaks SSH Connection

If setting an exit node caused SSH to drop:

```bash
# The fix is to ALWAYS include --exit-node-allow-lan-access=true
# If already disconnected, need physical/console access to run:
sudo tailscale set --exit-node=
# Then reconnect and retry with the flag
```

### Auto-Fix: Exit Node Not Working

```bash
# 1. Check if approved in admin console
tailscale status | grep "exit node"

# 2. Check IP forwarding on exit node server
sysctl net.ipv4.ip_forward
# If 0: enable it

# 3. Check if exit node can reach internet
ssh exit-node-server "curl -s https://example.com -o /dev/null -w '%{http_code}'"
```

## Auto-Fix: Slow Connection (Relay)

```bash
# Check connection type
tailscale status
# If shows "relay hkg" instead of "direct":

# 1. Run network check
tailscale netcheck
# Look for: "UDP" blocked or filtered

# 2. Try restarting
sudo systemctl restart tailscaled
sleep 5
tailscale status

# 3. If still relay: need to open UDP port 41641 on firewall
# This requires network admin access
```

## Auto-Fix: Device Shows Offline

```bash
# Check Tailscale daemon
sudo systemctl status tailscaled

# If not running:
sudo systemctl start tailscaled
sudo systemctl enable tailscaled

# If running but offline:
sudo tailscale up  # Re-authenticate
```

## Useful Commands

```bash
tailscale status              # All devices and connection status
tailscale ping DEVICE_IP      # Test connectivity to a device
tailscale netcheck            # Network diagnostics
tailscale ip -4               # Show this device's Tailscale IPv4
tailscale file send FILE HOST: # Send file to another device
tailscale set --exit-node=    # Stop using exit node
```
