# Claude Code Skills Collection

**English** | [中文](README_CN.md)

A growing collection of custom skills for [Claude Code](https://claude.ai/code), Anthropic's official CLI for Claude. These skills extend Claude's capabilities across Cloudflare deployment, network/proxy management, macOS automation, remote server operation, and IM platform bridging.

---

## Available Skills

### Cloudflare

| Skill | Description | Use Case |
|-------|-------------|----------|
| [cf-pages-deploy](skills/cloudflare/cf-pages-deploy/) | Deploy services on Cloudflare Pages with auto-fix for 1101 errors | Deploy web apps, proxy services, understand Pages vs Workers trade-offs |
| [cloudflare-tunnel](skills/cloudflare/cloudflare-tunnel/) | Set up cloudflared tunnels with WebSocket pitfall fixes | Expose local services, fix WebSocket instability, multi-service tunnels |
| [cf-auto-checkin](skills/cloudflare/cf-auto-checkin/) | Auto-checkin Workers with TG notifications, two login patterns | Daily auto sign-in, cookie-based or API login, cron triggers, multi-target TG push |

### Networking

| Skill | Description | Use Case |
|-------|-------------|----------|
| [ssh-persist](skills/networking/ssh-persist/) | Automated SSH key deployment and persistent connection management | Eliminate password prompts, prevent disconnects, speed up SSH |
| [tailscale-mesh](skills/networking/tailscale-mesh/) | Tailscale mesh networking: cross-platform SSH, exit nodes, device management | SSH between Windows/macOS/Linux via Tailscale, route internet through exit nodes |
| [proxy-multi-platform](skills/networking/proxy-multi-platform/) | Multi-platform proxy config management (QX/Surge/Clash) with 20+ incident lessons | Sync proxy configs across platforms, DNS routing, strategy groups |
| [vps-singbox](skills/networking/vps-singbox/) | VPS sing-box proxy server with 5 protocols, from 13-node production experience | Deploy VLESS Reality, Hysteria2, TUIC, Trojan on VPS with CDN relay |

### Automation

| Skill | Description | Use Case |
|-------|-------------|----------|
| [remote-gui](skills/automation/remote-gui/) | Operate GUI applications on headless Linux servers via SSH | Launch desktop apps, click buttons, fill forms on servers without monitors |
| [macos-accessibility](skills/automation/macos-accessibility/) | macOS Accessibility API automation with 3-layer fallback strategy | Build AI agents that control Mac apps, handle CJK input, AX API failures |

### Messaging

| Skill | Description | Use Case |
|-------|-------------|----------|
| [lark-im](skills/messaging/lark-im/) | Bridge multi-IM to multi-AI (Claude/Codex/Qwen/GLM) with model switching and 4-layer privacy | Chat with AI via Feishu/Telegram/QQ, switch models at runtime, fine-grained access control |

---

## Quick Start (5 minutes)

```bash
# 1. Clone
git clone https://github.com/18798aa12/claude-code-skills.git
cd claude-code-skills

# 2. Install skills by category
cp -r skills/cloudflare/* ~/.claude/skills/       # Cloudflare skills
cp -r skills/networking/* ~/.claude/skills/        # Networking skills
cp -r skills/automation/* ~/.claude/skills/        # Automation skills
cp -r skills/messaging/* ~/.claude/skills/         # Messaging skills

# Or install specific skills
cp -r skills/networking/vps-singbox ~/.claude/skills/
cp -r skills/cloudflare/cf-pages-deploy ~/.claude/skills/

# 3. Use in Claude Code
# Just describe what you want - Claude will automatically use the relevant skill:
#   "Deploy my app to Cloudflare Pages"
#   "Set up a sing-box server on my VPS with VLESS and Hysteria2"
#   "Sync my proxy config across QX, Surge, and Clash"
#   "Build a macOS agent that can control desktop apps"
```

## Prerequisites

- [Claude Code](https://claude.ai/code) CLI installed
- (For networking skills) SSH access to remote servers
- (For cloudflare skills) Cloudflare account with API token
- (For lark-im) Node.js >= 20, IM platform bot credentials
- (For macos-accessibility) macOS 14+, Xcode, Accessibility permission
- (Optional) [Tailscale](https://tailscale.com/) account for mesh networking

## Skill Highlights

### Each Skill Includes

- **When to use** — Clear trigger conditions
- **Auto-Setup Flow** — Step-by-step automated setup
- **Auto-Fix sections** — Common failures with automatic resolution
- **Troubleshooting** — Detailed diagnosis for edge cases
- **Production lessons** — Hard-won knowledge from real incidents

### Battle-Tested Knowledge

These skills encode lessons learned from:
- **20+ proxy config incidents** → proxy-multi-platform
- **13 VPS nodes across 8 countries** → vps-singbox
- **4 WebSocket deployment pitfalls** → cloudflare-tunnel
- **Workers 1101 blocking** → cf-pages-deploy
- **macOS AX API failures** → macos-accessibility
- **15+ agent safety incidents** → proxy-multi-platform
- **5 cookie parsing strategies** → cf-auto-checkin

## Contributing

PRs welcome! Skills are organized by category under `skills/`:

```
skills/
├── cloudflare/          # Cloudflare ecosystem
│   ├── cf-pages-deploy/
│   ├── cloudflare-tunnel/
│   └── cf-auto-checkin/
├── networking/          # Network & connectivity
│   ├── ssh-persist/
│   ├── tailscale-mesh/
│   ├── proxy-multi-platform/
│   └── vps-singbox/
├── automation/          # Automation tools
│   ├── remote-gui/
│   └── macos-accessibility/
└── messaging/           # Communication
    └── lark-im/
```

Each skill directory must contain a `SKILL.md` file with frontmatter:

```yaml
---
name: my-skill
description: One-line description
author: Your Name
version: 1.0.0
tags: [relevant, tags]
---
```

## Contributors

- **Jope Miler** ([@18798aa12](https://github.com/18798aa12)) — Author
- **Claude** (Anthropic) — Co-developer

## License

MIT License — see [LICENSE](LICENSE) for details.
