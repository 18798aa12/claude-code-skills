# Claude Code Skills Collection

**English** | [中文](README_CN.md)

A growing collection of custom skills for [Claude Code](https://claude.ai/code), Anthropic's official CLI for Claude. These skills extend Claude's capabilities to operate remote GUI applications, manage SSH connections, and configure Tailscale mesh networks.

---

## English

### Available Skills

| Skill | Description | Use Case |
|-------|-------------|----------|
| [lark-im](skills/lark-im/) | Bridge Lark/Feishu to Claude Code with model switching and privacy isolation | Chat with Claude Code via Feishu, switch models at runtime, 4-layer access control |
| [remote-gui](skills/remote-gui/) | Operate GUI applications on headless Linux servers via SSH | Launch desktop apps, click buttons, fill forms on servers without monitors |
| [ssh-persist](skills/ssh-persist/) | Automated SSH key deployment and persistent connection management | Eliminate password prompts, prevent disconnects, speed up SSH |
| [tailscale-mesh](skills/tailscale-mesh/) | Tailscale mesh networking: cross-platform SSH, exit nodes, device management | SSH between Windows/macOS/Linux via Tailscale, route internet through exit nodes |

### Quick Start (5 minutes)

```bash
# 1. Clone
git clone https://github.com/18798aa12/claude-code-skills.git
cd claude-code-skills

# 2. Install the skills you need
cp -r skills/remote-gui ~/.claude/skills/
cp -r skills/ssh-persist ~/.claude/skills/
cp -r skills/tailscale-mesh ~/.claude/skills/

# 3. Use in Claude Code
# Just describe what you want - Claude will automatically use the relevant skill:
#   "Set up SSH key auth to my server at 10.0.0.1"
#   "Launch the VPN client on my GPU server and log in"
#   "Configure Tailscale exit node on my VPS"
```

### Full Setup Guide

#### Prerequisites

- [Claude Code](https://claude.ai/code) CLI installed
- SSH access to at least one remote Linux server
- (Optional) [Tailscale](https://tailscale.com/) account for mesh networking

#### Step 1: Install Skills

```bash
# Clone the repository
git clone https://github.com/18798aa12/claude-code-skills.git

# Option A: Install all skills
cp -r claude-code-skills/skills/* ~/.claude/skills/

# Option B: Install specific skills
cp -r claude-code-skills/skills/remote-gui ~/.claude/skills/
cp -r claude-code-skills/skills/ssh-persist ~/.claude/skills/
cp -r claude-code-skills/skills/tailscale-mesh ~/.claude/skills/

# Verify installation
ls ~/.claude/skills/
# Should show: remote-gui/  ssh-persist/  tailscale-mesh/
```

#### Step 2: Configure SSH Access

Before using `remote-gui` or `ssh-persist`, ensure you can SSH to your server:

```bash
# Test basic SSH connectivity
ssh user@your-server-ip "echo connected"

# If using Tailscale
ssh user@100.x.x.x "echo connected"
```

#### Step 3: Use the Skills

Start Claude Code and describe your task. Claude will automatically detect which skill to use:

```bash
# Start Claude Code
claude

# Then tell Claude what you want:
# > "Set up passwordless SSH to my GPU server at 100.100.203.100 with user zqs"
# > "Open the VPN client GUI on my server and log in with email test@example.com"
# > "Make my VPS an exit node so my GPU server can access the internet"
```

---

### Skill Details

#### remote-gui — Remote GUI Operation

**What it does**: Lets Claude see and interact with desktop applications running on headless Linux servers (servers without a monitor).

**How it works**:

```
┌─────────────────────────────────────────────────┐
│              Remote Server (Headless)             │
│                                                  │
│  ┌──────────────────────────────────────┐        │
│  │  Xvfb — Virtual Display (:99)       │        │
│  │  ┌──────────────────────────────┐   │        │
│  │  │  fluxbox — Window Manager    │   │        │
│  │  │  ┌──────────────────────┐   │   │        │
│  │  │  │  Your GUI App        │   │   │        │
│  │  │  │  (VPN, IDE, etc.)    │   │   │        │
│  │  │  └──────────────────────┘   │   │        │
│  │  └──────────────────────────────┘   │        │
│  └──────────────────────────────────────┘        │
│                                                  │
│  scrot → screenshot.png                          │
│  xdotool → click(x,y) / type("text")            │
└──────────┬──────────────────────┬────────────────┘
           │ SCP (download)       │ SSH (commands)
┌──────────▼──────────────────────▼────────────────┐
│              Your Computer (Claude Code)          │
│                                                  │
│  1. Read screenshot → understand UI layout        │
│  2. Decide action → "click login button at 640,500│
│  3. Send xdotool command via SSH                  │
│  4. Take new screenshot → verify success          │
│  5. Repeat until done                            │
└──────────────────────────────────────────────────┘
```

**First-time setup** (auto-installed by Claude):

```bash
# On the remote server (requires sudo)
sudo apt install -y xvfb fluxbox scrot xdotool imagemagick
```

**Manual usage** (if you want to run the commands yourself):

```bash
# 1. Start virtual display
Xvfb :99 -screen 0 1280x720x24 &>/dev/null &
export DISPLAY=:99
fluxbox &>/dev/null &

# 2. Launch your GUI app
/path/to/your/app &
sleep 3

# 3. Take screenshot
scrot /tmp/screen.png

# 4. Transfer to local and view
scp server:/tmp/screen.png ./screen.png

# 5. Interact
xdotool mousemove 640 330    # Move mouse
xdotool click 1               # Left click
xdotool type 'hello@email.com'  # Type text
xdotool key Return             # Press Enter

# 6. Screenshot again to verify
scrot /tmp/screen2.png
```

**Supported interactions**:

| Action | Command | Example |
|--------|---------|---------|
| Move mouse | `xdotool mousemove X Y` | `xdotool mousemove 640 330` |
| Left click | `xdotool click 1` | Click at current position |
| Right click | `xdotool click 3` | Open context menu |
| Double click | `xdotool click --repeat 2 1` | Open file |
| Type text | `xdotool type 'text'` | `xdotool type 'user@email.com'` |
| Type slowly | `xdotool type --delay 50 'text'` | For apps that miss fast typing |
| Press key | `xdotool key <key>` | `xdotool key Return` |
| Key combo | `xdotool key ctrl+a` | Select all |
| Scroll up | `xdotool click 4` | Mouse wheel up |
| Scroll down | `xdotool click 5` | Mouse wheel down |
| Find window | `xdotool search --name "Title"` | Get window ID by title |
| Focus window | `xdotool windowactivate <id>` | Bring window to front |

**Limitations**:
- ~3-5 seconds per action cycle (screenshot transfer + processing)
- Requires sudo for initial package installation
- No audio support
- Very small text may be hard to read (increase screen resolution)

---

#### ssh-persist — SSH Persistent Connection

**What it does**: Sets up passwordless SSH key authentication and optimizes connection settings for reliability.

**The problem**: Every SSH command requires password → slow, triggers fail2ban after too many attempts, connections drop when idle.

**The solution**: SSH key auth + keepalive configuration.

**Step-by-step setup**:

```bash
# Step 1: Check if you have an SSH key
ls ~/.ssh/id_ed25519.pub
# If not found, generate one:
ssh-keygen -t ed25519 -f ~/.ssh/id_ed25519 -N ""

# Step 2: Copy your key to the remote server
ssh-copy-id -i ~/.ssh/id_ed25519.pub user@server

# If that fails (permission issues), do it manually:
cat ~/.ssh/id_ed25519.pub | ssh user@server "mkdir -p ~/.ssh && cat >> ~/.ssh/authorized_keys"

# If authorized_keys has immutable flag:
ssh user@server "sudo chattr -i ~/.ssh/authorized_keys"
cat ~/.ssh/id_ed25519.pub | ssh user@server "cat >> ~/.ssh/authorized_keys"
ssh user@server "sudo chattr +i ~/.ssh/authorized_keys"

# Step 3: Configure ~/.ssh/config
cat >> ~/.ssh/config << 'EOF'
Host myserver
    HostName 10.0.0.1
    User myuser
    IdentityFile ~/.ssh/id_ed25519
    ServerAliveInterval 15
    ServerAliveCountMax 20
    ConnectTimeout 30
    TCPKeepAlive yes
EOF

# Step 4: Test
ssh myserver "echo 'Passwordless SSH works!'"
```

**Configuration reference**:

```
Host <alias>                    # Name you'll use: ssh <alias>
    HostName <ip-or-domain>     # Server address
    User <username>             # SSH username
    Port <port>                 # SSH port (default: 22)
    IdentityFile <key-path>     # Path to private key
    ServerAliveInterval 15      # Send keepalive every N seconds
    ServerAliveCountMax 20      # Max missed keepalives
    ConnectTimeout 30           # Connection timeout (seconds)
    TCPKeepAlive yes            # TCP-level keepalive

    # Linux/macOS only (NOT Windows):
    ControlMaster auto          # Reuse connections
    ControlPath ~/.ssh/cm-%r@%h:%p
    ControlPersist 4h           # Keep master alive for 4 hours
```

**Platform differences**:

| Feature | Linux/macOS | Windows (Git Bash) |
|---------|-------------|-------------------|
| Key auth | Full support | Full support |
| ControlMaster | Full support (~0.1s reuse) | Not supported (socket issues) |
| Keepalive | Full support | Full support |
| Connection speed | ~0.1s (reuse) / ~2s (new) | ~3-4s per command |

---

#### tailscale-mesh — Tailscale Mesh Networking

**What it does**: Configures Tailscale mesh networks so all your devices (Windows, macOS, Linux) can communicate directly, regardless of firewalls or NATs.

**Key concepts**:

| Concept | What it means |
|---------|--------------|
| **Mesh Network** | All devices connect directly to each other (peer-to-peer) |
| **Tailscale IP** | Each device gets a `100.x.x.x` address that works everywhere |
| **Exit Node** | A device that routes other devices' internet traffic through itself |
| **Tailscale SSH** | SSH without OpenSSH, using Tailscale's built-in SSH (Linux/macOS only) |

**Full setup — making all devices SSH-accessible**:

##### Linux Server (e.g., GPU server)

```bash
# Install Tailscale
curl -fsSL https://tailscale.com/install.sh | sh

# Join network + enable SSH + advertise as exit node
sudo tailscale up --ssh --advertise-exit-node

# Enable IP forwarding (required for exit node)
echo 'net.ipv4.ip_forward = 1' | sudo tee -a /etc/sysctl.d/99-tailscale.conf
echo 'net.ipv6.conf.all.forwarding = 1' | sudo tee -a /etc/sysctl.d/99-tailscale.conf
sudo sysctl -p /etc/sysctl.d/99-tailscale.conf

# Check your Tailscale IP
tailscale ip -4
# Example output: 100.100.203.100
```

##### macOS

```bash
# Install
brew install tailscale
# Or download from: https://tailscale.com/download/mac

# Join network + enable SSH
sudo tailscale up --ssh

# Check IP
tailscale ip -4
```

##### Windows

```powershell
# Install via winget
winget install Tailscale.Tailscale

# Or download from: https://tailscale.com/download/windows
# Launch Tailscale from system tray and sign in

# IMPORTANT: Windows cannot run Tailscale SSH server
# Instead, enable OpenSSH Server:
Add-WindowsCapability -Online -Name OpenSSH.Server~~~~0.0.1.0
Start-Service sshd
Set-Service -Name sshd -StartupType 'Automatic'

# Set password authentication or deploy SSH keys
# Now other devices can: ssh windowsuser@100.x.x.x
```

##### Verify cross-platform SSH

```bash
# From any device to Linux:
ssh user@100.100.203.100     # Uses Tailscale SSH or OpenSSH

# From any device to macOS:
ssh user@100.x.x.x           # Uses Tailscale SSH

# From any device to Windows:
ssh windowsuser@100.108.97.45  # Uses OpenSSH Server

# From Linux/Mac to any device (using Tailscale SSH):
ssh user@hostname              # Uses Tailscale hostname
```

##### Using Exit Nodes

When a device has no internet but can reach another device via Tailscale:

```bash
# On the device that needs internet:
sudo tailscale set --exit-node=100.127.35.1 --exit-node-allow-lan-access=true

# Verify internet works:
curl -s https://example.com -o /dev/null -w '%{http_code}'
# Should output: 200

# Stop using exit node:
sudo tailscale set --exit-node=

# WARNING: Always use --exit-node-allow-lan-access=true
# Otherwise your SSH connection may break!
```

##### Useful commands

```bash
# See all devices
tailscale status

# Ping a device (test connectivity)
tailscale ping 100.100.203.100

# Network diagnostics
tailscale netcheck

# See file transfer capability
tailscale file send myfile.txt hostname:
```

---

### Troubleshooting

<details>
<summary><b>remote-gui: Screenshot is all black</b></summary>

The window manager isn't running. Start it:
```bash
export DISPLAY=:99
fluxbox &>/dev/null &
sleep 2
scrot /tmp/test.png  # Should now show the desktop
```
</details>

<details>
<summary><b>ssh-persist: "Permission denied" after deploying key</b></summary>

Common causes:
1. `authorized_keys` has immutable flag: `sudo chattr -i ~/.ssh/authorized_keys`
2. `.ssh` directory wrong owner: `sudo chown user:user ~/.ssh ~/.ssh/authorized_keys`
3. Wrong permissions: `chmod 700 ~/.ssh && chmod 600 ~/.ssh/authorized_keys`
</details>

<details>
<summary><b>tailscale: "relay hkg" instead of direct connection</b></summary>

Devices are communicating through a relay instead of directly. This is slower.
- Open UDP port 41641 on both devices' firewalls
- Run `tailscale netcheck` to see what's blocking direct connections
- Try restarting Tailscale: `sudo systemctl restart tailscaled`
</details>

<details>
<summary><b>tailscale: Exit node set but internet still doesn't work</b></summary>

1. Approve the exit node in [Tailscale admin console](https://login.tailscale.com/admin/machines)
2. Enable IP forwarding on the exit node server
3. Check with: `curl -s --connect-timeout 5 https://example.com`
</details>

<details>
<summary><b>Windows: Cannot SSH to Windows machine</b></summary>

Windows doesn't support Tailscale SSH. Use OpenSSH Server instead:
```powershell
# Install (Admin PowerShell)
Add-WindowsCapability -Online -Name OpenSSH.Server~~~~0.0.1.0
Start-Service sshd
Set-Service -Name sshd -StartupType 'Automatic'

# Then from other devices:
ssh windowsuser@<windows-tailscale-ip>
```
</details>

---

## Contributing

PRs welcome! Each skill is a directory under `skills/` containing a `SKILL.md` file.

```
skills/my-skill/
├── SKILL.md          # Skill definition (required, read by Claude Code)
└── scripts/          # Helper scripts (optional)
```

## Contributors

- **Jope Miler** ([@18798aa12](https://github.com/18798aa12)) — Author
- **Claude** (Anthropic) — Co-developer

## License

MIT License — see [LICENSE](LICENSE) for details.
