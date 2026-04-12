# Claude Code Skills Collection

[English](#english) | [中文](#中文)

A growing collection of custom skills for [Claude Code](https://claude.ai/code), Anthropic's official CLI for Claude.

---

## English

### Overview

This repository contains reusable skills that extend Claude Code's capabilities. Each skill is a self-contained module that can be installed independently.

### Available Skills

| Skill | Description | Use Case |
|-------|-------------|----------|
| [remote-gui](skills/remote-gui/) | Operate GUI applications on headless Linux servers via SSH | Launch desktop apps, click buttons, fill forms on servers without monitors |
| [ssh-persist](skills/ssh-persist/) | Automated SSH key deployment and persistent connection management | Eliminate password prompts, prevent disconnects, speed up SSH |
| [tailscale-mesh](skills/tailscale-mesh/) | Tailscale mesh networking: cross-platform SSH, exit nodes, device management | SSH between Windows/macOS/Linux via Tailscale, route internet through exit nodes |

### Quick Install

```bash
# Clone the repository
git clone https://github.com/18798aa12/claude-code-skills.git

# Install a single skill
cp -r claude-code-skills/skills/remote-gui ~/.claude/skills/

# Or install all skills at once
cp -r claude-code-skills/skills/* ~/.claude/skills/
```

### Skill: remote-gui

**Problem**: Claude Code cannot interact with GUI applications on remote servers. Headless servers have no display, and tools like VNC require manual browser access that Claude cannot control.

**Solution**: A screenshot-and-click automation loop using standard Linux tools:

```
┌─────────────────────────────────────────────────┐
│                Remote Server                     │
│                                                  │
│  Xvfb (Virtual Display :99)                      │
│  ├── fluxbox (Window Manager)                    │
│  └── Your GUI App (e.g., VPN client, IDE)        │
│                                                  │
│  scrot → screenshot.png  ← xdotool click/type    │
└───────────┬──────────────────────┬───────────────┘
            │ SCP download         │ SSH command
┌───────────▼──────────────────────▼───────────────┐
│              Claude Code (Local)                  │
│                                                  │
│  Read screenshot → Understand UI → Decide action  │
│  → Send xdotool command → Take new screenshot     │
│  → Verify result → Repeat                        │
└──────────────────────────────────────────────────┘
```

**How it works step by step**:

1. **Setup** (one-time): Install `Xvfb`, `fluxbox`, `scrot`, `xdotool` on the remote server
2. **Launch**: Start virtual display and window manager, then launch the target GUI application
3. **Screenshot**: Capture the screen with `scrot`, transfer to local via SCP
4. **Read**: Claude reads the screenshot image to understand the current UI state
5. **Act**: Claude sends mouse movements, clicks, and keyboard input via `xdotool`
6. **Verify**: Take another screenshot to confirm the action succeeded
7. **Repeat**: Continue the loop until the task is complete

**Requirements**:
- Remote server: Ubuntu/Debian Linux with `apt` package manager
- SSH access to the server (password or key-based)
- Packages (auto-installed): `xvfb`, `fluxbox`, `scrot`, `xdotool`, `imagemagick`

**Example Usage**:

```
User: Log into the VPN client on my GPU server

Claude: Setting up virtual display...
        [installs xvfb, fluxbox, scrot, xdotool]
        [starts Xvfb :99, launches fluxbox]
        [launches VPN client]
        [takes screenshot → sees login form]
        [clicks email field → types email]
        [clicks password field → types password]
        [clicks login button]
        [takes screenshot → login successful!]
```

### Skill: ssh-persist

**Problem**: SSH connections to remote servers are slow (password authentication every time), frequently disconnect (no keepalive), and may trigger fail2ban after repeated reconnections.

**Solution**: Automated SSH key deployment and optimized connection configuration.

**What it does**:

1. **Key Setup**: Generates or reuses existing Ed25519 SSH key
2. **Key Deployment**: Copies public key to remote server's `authorized_keys` (handles permission issues, immutable file attributes, owner mismatches)
3. **SSH Config**: Creates/updates `~/.ssh/config` with:
   - Host alias (e.g., `ssh myserver` instead of `ssh user@10.0.0.1`)
   - `IdentityFile` for passwordless auth
   - `ServerAliveInterval` / `ServerAliveCountMax` for keepalive
   - `TCPKeepAlive` to prevent idle disconnects
4. **Verification**: Tests the connection and reports latency

**Before vs After**:

| Metric | Before | After |
|--------|--------|-------|
| Authentication | Password (slow, triggers fail2ban) | SSH key (instant, no fail2ban) |
| Command | `ssh user@100.100.203.100` | `ssh l40` |
| Keepalive | None (disconnects after idle) | Every 15s heartbeat |
| Reconnect on failure | Manual | Auto-retry |

**Example Usage**:

```
User: Set up persistent SSH to my L40 GPU server

Claude: Checking existing SSH keys... found id_ed25519
        Deploying key to 100.100.203.100...
        [handles immutable flag on authorized_keys]
        Configuring ~/.ssh/config with alias 'l40'...
        Testing connection... 3.6s, no password required.
        Done! Use `ssh l40` from now on.
```

### Creating New Skills

Each skill is a directory under `skills/` containing:

```
skills/my-skill/
├── SKILL.md          # Skill definition (required)
├── README.md         # Detailed documentation
└── scripts/          # Helper scripts (optional)
    └── setup.sh
```

The `SKILL.md` file follows the Claude Code skill format with YAML frontmatter.

---

## 中文

### 概述

这是一个持续增长的 [Claude Code](https://claude.ai/code) 自定义技能集合。每个技能都是独立模块，可以单独安装使用。

### 可用技能

| 技能 | 描述 | 使用场景 |
|------|------|---------|
| [remote-gui](skills/remote-gui/) | 通过 SSH 在无显示器的 Linux 服务器上操作 GUI 应用 | 在 GPU 服务器上启动桌面程序、点击按钮、填写表单 |
| [ssh-persist](skills/ssh-persist/) | 自动部署 SSH 密钥和持久化连接管理 | 免密码登录、防断连、加速 SSH 连接 |
| [tailscale-mesh](skills/tailscale-mesh/) | Tailscale 组网：跨平台 SSH、出口节点、设备管理 | Windows/macOS/Linux 互相 SSH、通过出口节点访问外网 |

### 快速安装

```bash
# 克隆仓库
git clone https://github.com/18798aa12/claude-code-skills.git

# 安装单个技能
cp -r claude-code-skills/skills/remote-gui ~/.claude/skills/

# 或安装全部技能
cp -r claude-code-skills/skills/* ~/.claude/skills/
```

### 技能：remote-gui（远程 GUI 操作）

**解决的问题**：Claude Code 无法操作远程服务器上的 GUI 应用。无显示器的服务器没有图形界面，VNC 等方案需要手动在浏览器中操作，Claude 无法控制。

**解决方案**：基于标准 Linux 工具的"截图-识别-点击"自动化循环：

```
┌─────────────────────────────────────────────────┐
│              远程服务器                            │
│                                                  │
│  Xvfb (虚拟显示器 :99)                            │
│  ├── fluxbox (轻量窗口管理器)                      │
│  └── 你的 GUI 应用 (如 VPN 客户端、IDE)            │
│                                                  │
│  scrot → 截图.png    ← xdotool 点击/输入          │
└───────────┬──────────────────────┬───────────────┘
            │ SCP 下载              │ SSH 命令
┌───────────▼──────────────────────▼───────────────┐
│              Claude Code (本地)                    │
│                                                  │
│  读取截图 → 理解界面 → 决定操作 → 发送命令          │
│  → 再截图 → 验证结果 → 循环                       │
└──────────────────────────────────────────────────┘
```

**工作流程**：

1. **环境准备**（首次自动完成）：在远程服务器安装 `Xvfb`、`fluxbox`、`scrot`、`xdotool`
2. **启动**：创建虚拟显示器和窗口管理器，然后启动目标 GUI 应用
3. **截图**：用 `scrot` 截取屏幕，通过 SCP 传到本地
4. **识别**：Claude 读取截图，理解当前界面状态（按钮位置、输入框、文字等）
5. **操作**：Claude 通过 `xdotool` 发送鼠标移动、点击和键盘输入
6. **验证**：再次截图确认操作成功
7. **循环**：重复直到任务完成

**服务器要求**：
- Ubuntu/Debian Linux，有 `apt` 包管理器
- SSH 访问权限（密码或密钥均可）
- 所需软件包会在首次使用时自动安装

**使用示例**：

```
用户：帮我在 GPU 服务器上登录 VPN 客户端

Claude：正在配置虚拟显示器...
       [安装 xvfb, fluxbox, scrot, xdotool]
       [启动 Xvfb :99 和 fluxbox]
       [启动 VPN 客户端]
       [截图 → 看到登录界面]
       [点击邮箱输入框 → 输入邮箱]
       [点击密码输入框 → 输入密码]
       [点击登录按钮]
       [截图 → 登录成功！]
```

### 技能：ssh-persist（SSH 持久化连接）

**解决的问题**：SSH 连接慢（每次都要输密码）、频繁断连（没有心跳保活）、重连太多次被 fail2ban 封禁。

**解决方案**：自动化 SSH 密钥部署 + 优化连接配置。

**功能**：

1. **密钥配置**：生成或复用现有的 Ed25519 SSH 密钥
2. **密钥部署**：将公钥复制到远程服务器的 `authorized_keys`（自动处理权限问题、immutable 文件属性、所有者不匹配等）
3. **SSH 配置**：创建/更新 `~/.ssh/config`，包含：
   - 主机别名（如 `ssh l40` 代替 `ssh user@100.100.203.100`）
   - 免密登录配置
   - 心跳保活（15 秒间隔）
   - TCP KeepAlive 防止空闲断连
4. **验证**：测试连接并报告延迟

**使用前后对比**：

| 指标 | 之前 | 之后 |
|------|------|------|
| 认证方式 | 密码（慢，触发 fail2ban） | SSH 密钥（即时，安全） |
| 连接命令 | `ssh user@100.100.203.100` | `ssh l40` |
| 心跳保活 | 无（空闲断连） | 每 15 秒 |
| 连接速度 | ~10-30 秒 | ~3-4 秒 |

---

## Contributors

- **Zhou Qishun** ([@18798aa12](https://github.com/18798aa12)) — Author
- **Claude** (Anthropic) — Co-developer

## License

MIT License - see [LICENSE](LICENSE) for details.
