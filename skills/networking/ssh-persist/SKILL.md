---
name: ssh-persist
description: Automated SSH key deployment and persistent connection management. Auto-detects and fixes permission issues, immutable flags, and connection problems.
author: Jope Miler, Claude
version: 1.0.0
tags: [ssh, key, authentication, persistent, connection, keepalive]
---

# SSH Persistent Connection

Automates SSH key-based authentication setup and optimizes connection reliability. Automatically detects and fixes common SSH issues.

## When to use

- First time connecting to a new server
- SSH keeps asking for password
- Connections frequently drop or timeout
- Getting locked out by fail2ban

## Auto-Setup Flow

When this skill is triggered, Claude should automatically handle the entire process:

### Step 1: Check/Generate SSH Key
```bash
# Check existing key
if [ -f ~/.ssh/id_ed25519.pub ]; then
    echo "Key exists"
    cat ~/.ssh/id_ed25519.pub
else
    ssh-keygen -t ed25519 -f ~/.ssh/id_ed25519 -N "" -C "$(whoami)@$(hostname)"
fi
```

### Step 2: Deploy Key to Server (with auto-fix)
```bash
# Try standard method first
ssh-copy-id -i ~/.ssh/id_ed25519.pub user@server 2>&1

# If that fails, try manual method
cat ~/.ssh/id_ed25519.pub | ssh user@server "cat >> ~/.ssh/authorized_keys" 2>&1
```

### Auto-Fix: Permission Denied on authorized_keys
```bash
# Check file attributes
ssh user@server "lsattr ~/.ssh/authorized_keys 2>/dev/null"
# If immutable flag (i) is set:
ssh user@server "echo 'PASSWORD' | sudo -S chattr -i ~/.ssh/authorized_keys"
# Write key
PUB=$(cat ~/.ssh/id_ed25519.pub)
ssh user@server "echo '$PUB' >> ~/.ssh/authorized_keys"
# Restore immutable
ssh user@server "echo 'PASSWORD' | sudo -S chattr +i ~/.ssh/authorized_keys"
```

### Auto-Fix: Wrong Owner on .ssh Directory
```bash
# Check ownership
ssh user@server "ls -la ~/.ssh/"
# If owned by different user:
ssh user@server "echo 'PASSWORD' | sudo -S chown user:user ~/.ssh ~/.ssh/authorized_keys"
```

### Auto-Fix: Wrong Permissions
```bash
ssh user@server "chmod 700 ~/.ssh; chmod 600 ~/.ssh/authorized_keys"
```

### Step 3: Configure SSH Config
```bash
# Check if host already configured
grep -q "Host ALIAS" ~/.ssh/config 2>/dev/null

# Add or update config
cat >> ~/.ssh/config << EOF
Host ALIAS
    HostName SERVER_IP
    User USERNAME
    IdentityFile ~/.ssh/id_ed25519
    ServerAliveInterval 15
    ServerAliveCountMax 20
    ConnectTimeout 30
    TCPKeepAlive yes
EOF
```

### Step 4: Verify
```bash
# Test passwordless connection
ssh ALIAS "echo 'Key auth OK'; hostname"

# Measure speed
time ssh ALIAS "echo connected"
```

## Auto-Fix: fail2ban Lockout

If previous password attempts triggered fail2ban:
```bash
# Wait 30-60 minutes for auto-unban
# Or if you have sudo on the server via another path:
ssh other-user@server "sudo fail2ban-client set sshd unbanip YOUR_IP"
```

After fixing, key-based auth prevents future lockouts (no failed password attempts).

## Configuration Reference

```
Host <alias>
    HostName <ip>              # Server IP or domain
    User <username>            # SSH username
    Port <port>                # Default: 22
    IdentityFile <key>         # Private key path
    ServerAliveInterval 15     # Keepalive interval (seconds)
    ServerAliveCountMax 20     # Max missed keepalives
    ConnectTimeout 30          # Connection timeout
    TCPKeepAlive yes           # TCP keepalive

    # Linux/macOS only:
    ControlMaster auto
    ControlPath ~/.ssh/cm-%r@%h:%p
    ControlPersist 4h
```

## Platform Notes

| Feature | Linux/macOS | Windows |
|---------|-------------|---------|
| Key auth | Full | Full |
| ControlMaster | Full (~0.1s) | Not supported |
| Keepalive | Full | Full |
| Speed | ~0.1s reuse / ~2s new | ~3-4s |
