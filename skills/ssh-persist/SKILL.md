---
name: ssh-persist
description: Automated SSH key deployment and persistent connection management for reliable remote server access
author: Zhou Qishun, Claude
version: 1.0.0
tags: [ssh, key, authentication, persistent, connection, keepalive]
---

# SSH Persistent Connection

Automates SSH key-based authentication setup and optimizes connection reliability.

## When to use

- First time connecting to a new server (set up passwordless auth)
- Frequent SSH disconnections or timeouts
- Getting locked out by fail2ban due to repeated password attempts
- Want faster SSH connections with host aliases

## What it does

### 1. SSH Key Setup

Checks for existing Ed25519 key or generates a new one:

```bash
# Check existing
ls ~/.ssh/id_ed25519.pub

# Generate if missing
ssh-keygen -t ed25519 -C "user@host" -f ~/.ssh/id_ed25519 -N ""
```

### 2. Key Deployment

Copies public key to remote server, handling common issues:

```bash
# Standard method
ssh-copy-id -i ~/.ssh/id_ed25519.pub user@server

# If authorized_keys has immutable flag (common on shared servers)
ssh user@server "sudo chattr -i ~/.ssh/authorized_keys"
cat ~/.ssh/id_ed25519.pub | ssh user@server "cat >> ~/.ssh/authorized_keys"
ssh user@server "sudo chattr +i ~/.ssh/authorized_keys"

# If .ssh directory has wrong owner
ssh user@server "sudo chown user:user ~/.ssh ~/.ssh/authorized_keys"
```

### 3. SSH Config

Creates optimized `~/.ssh/config` entry:

```
Host myserver
    HostName 10.0.0.1
    User myuser
    IdentityFile ~/.ssh/id_ed25519
    ServerAliveInterval 15      # Send keepalive every 15 seconds
    ServerAliveCountMax 20      # Allow 20 missed keepalives before disconnect
    ConnectTimeout 30           # 30 second connection timeout
    TCPKeepAlive yes            # Enable TCP-level keepalive
```

### 4. Connection Test

```bash
# Verify passwordless auth works
ssh myserver "echo OK; hostname"

# Measure connection speed
time ssh myserver "echo connected"
```

## Configuration Options

| Option | Default | Description |
|--------|---------|-------------|
| `ServerAliveInterval` | 15 | Seconds between keepalive packets |
| `ServerAliveCountMax` | 20 | Max missed keepalives before disconnect |
| `ConnectTimeout` | 30 | Connection timeout in seconds |
| `TCPKeepAlive` | yes | Enable TCP keepalive |

## Common Issues and Solutions

| Problem | Cause | Solution |
|---------|-------|----------|
| `Permission denied (publickey)` | Key not deployed correctly | Re-run key deployment |
| `authorized_keys: Operation not permitted` | File has immutable attribute | `sudo chattr -i` before writing |
| `.ssh owned by wrong user` | Admin created the directory | `sudo chown user:user ~/.ssh` |
| Connection drops after idle | No keepalive configured | Add `ServerAliveInterval 15` |
| `fail2ban` blocking IP | Too many password attempts | Switch to key auth (no passwords) |
| Windows ControlMaster fails | Windows SSH doesn't support Unix sockets | Don't use ControlMaster on Windows, rely on key auth speed |

## Platform Notes

### Windows (Git Bash / MSYS2)

- SSH ControlMaster/ControlPersist does **not** work reliably
- Key-based auth + keepalive is the best available solution
- Connection time: ~3-4 seconds per command

### Linux/macOS

- Full ControlMaster support available:
  ```
  ControlMaster auto
  ControlPath ~/.ssh/cm-%r@%h:%p
  ControlPersist 4h
  ```
- First connection: ~3 seconds, subsequent: <0.1 seconds

## Security Notes

- Uses Ed25519 keys (most secure and fastest SSH key type)
- Never stores passwords in files or scripts
- Key deployment restores immutable flags after modification
- Compatible with fail2ban (key auth doesn't trigger lockout)
