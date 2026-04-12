# Claude Code 技能合集

[English](README.md) | **中文**

一个持续增长的 [Claude Code](https://claude.ai/code) 自定义技能集合。这些技能扩展了 Claude 的能力：桥接 IM 平台（飞书/Lark）、操作远程 GUI 应用、管理 SSH 连接、配置 Tailscale 组网。

## 可用技能

| 技能 | 描述 | 使用场景 |
|------|------|---------|
| [lark-im](skills/lark-im/) | 多 IM 平台接入多 AI 后端：底模切换 + 4 层隐私隔离 | 飞书/Telegram/QQ 等接入 Claude/Codex/Qwen/GLM 等，运行时切模型，精细权限控制 |
| [remote-gui](skills/remote-gui/) | 通过 SSH 在无显示器的 Linux 服务器上操作 GUI 应用 | 在 GPU 服务器上启动桌面程序、点击按钮、填写表单 |
| [ssh-persist](skills/ssh-persist/) | 自动部署 SSH 密钥和持久化连接管理 | 免密码登录、防断连、加速 SSH 连接 |
| [tailscale-mesh](skills/tailscale-mesh/) | Tailscale 组网：跨平台 SSH、出口节点、设备管理 | Windows/macOS/Linux 互相 SSH、通过出口节点访问外网 |

## 快速开始（5 分钟）

```bash
# 1. 克隆仓库
git clone https://github.com/18798aa12/claude-code-skills.git
cd claude-code-skills

# 2. 安装需要的技能
cp -r skills/lark-im ~/.claude/skills/
cp -r skills/remote-gui ~/.claude/skills/
cp -r skills/ssh-persist ~/.claude/skills/
cp -r skills/tailscale-mesh ~/.claude/skills/

# 3. 在 Claude Code 中使用
# 直接描述你的需求，Claude 会自动选择合适的技能：
#   "帮我搭建一个飞书接入 Claude Code 的机器人"
#   "帮我配置到服务器 10.0.0.1 的免密 SSH"
#   "在 GPU 服务器上启动 VPN 客户端并登录"
#   "把 VPS 配成出口节点让 GPU 服务器能上网"
```

## 完整配置指南

### 前提条件

- 已安装 [Claude Code](https://claude.ai/code) CLI
- （lark-im 需要）Node.js >= 20、[飞书](https://www.feishu.cn/)开放平台应用（含 Bot 能力）、Claude OAuth token
- （remote-gui / ssh-persist 需要）至少一台可 SSH 访问的远程 Linux 服务器
- （可选）[Tailscale](https://tailscale.com/) 账号用于组网

### 第一步：安装技能

```bash
# 克隆仓库
git clone https://github.com/18798aa12/claude-code-skills.git

# 方式 A：安装全部技能
cp -r claude-code-skills/skills/* ~/.claude/skills/

# 方式 B：安装指定技能
cp -r claude-code-skills/skills/lark-im ~/.claude/skills/
cp -r claude-code-skills/skills/remote-gui ~/.claude/skills/

# 验证安装
ls ~/.claude/skills/
# 应该看到: lark-im/  remote-gui/  ssh-persist/  tailscale-mesh/
```

### 第二步：确保 SSH 可用

```bash
# 测试能否连接到服务器
ssh user@your-server "echo OK"

# 如果使用 Tailscale
ssh user@100.x.x.x "echo OK"
```

### 第三步：开始使用

启动 Claude Code，描述你的任务即可：

```bash
claude
# > "帮我在 GPU 服务器上登录 VPN 客户端"
# > "配置免密 SSH 到 100.100.203.100"
# > "设置 Tailscale 出口节点"
```

## 各技能详细说明

### lark-im — 多 IM 平台接入 AI 编程助手

**解决的问题**：想通过 IM（飞书、Telegram、QQ 等）和 AI 编程助手对话，同时需要安全地限制 AI 的文件访问范围，并灵活切换底层模型。

**工作原理**：

```
IM 用户（飞书 / Telegram / QQ / 钉钉 / 企微 / 微信）
    │
    ↓  WebSocket / Bot API
    │
┌───────────────────────────────┐
│  @wu529778790/open-im         │  多 IM ↔ 多 AI 桥接
│  + patch-package 补丁         │  注入 canUseTool 回调
└───────────┬───────────────────┘
            │
    ┌───────┼────────┐
    ↓       ↓        ↓
┌────────┐┌────────┐┌──────────┐
│ Claude ││ Codex  ││CodeBuddy │  AI 后端（可选）
│  SDK   ││  CLI   ││   CLI    │
└───┬────┘└───┬────┘└────┬─────┘
    │         │          │
    ↓         ↓          ↓
 MCP 服务器 + 工具（canUseTool 过滤）
```

> Claude 后端还支持自定义端点，可接 **Qwen、GLM、DeepSeek、Kimi** 等任意 OpenAI 兼容 API。

**快速搭建**：

```bash
# 1. 创建项目
mkdir my-im-bot && cd my-im-bot
npm init -y
npm install @wu529778790/open-im @anthropic-ai/claude-agent-sdk ws
npm install -D patch-package

# 2. 飞书凭证存到项目外（安全隔离）
mkdir -p ~/.open-im
# 创建 ~/.open-im/config.json（写入 appId 和 appSecret）
# 创建 ~/.open-im/token（写入 Claude OAuth token）

# 3. 应用隐私补丁（注入 canUseTool 回调）
# 补丁内容见 SKILL.md
npx patch-package @wu529778790/open-im
```

**支持 3 种 AI 后端**：

| 后端 | 提供商 | 模型 | 认证方式 |
|------|--------|------|---------|
| **Claude**（原生） | Anthropic | Opus 4.6/4.5, Sonnet 4.6, Haiku 4.5 | OAuth token / API key |
| **Claude**（自定义端点） | 任意 OpenAI 兼容 API | **Qwen、GLM、DeepSeek、Kimi** 等 | `ANTHROPIC_BASE_URL` + `ANTHROPIC_AUTH_TOKEN` |
| **Codex** | OpenAI | GPT-4o, o3 等 | `OPENAI_API_KEY` |
| **CodeBuddy** | 腾讯 | 腾讯 AI 模型 | `CODEBUDDY_API_KEY` |

**底模切换** — 四种方式：

| 方式 | 怎么做 | 适用场景 |
|------|--------|---------|
| 切换 AI 后端 | config.json 改 `"aiCommand": "codex"` | 整体换提供商 |
| 修改补丁默认值 | 改 `model: 'claude-sonnet-4-6'` | 永久切换 Claude 模型 |
| 环境变量覆盖 | `ANTHROPIC_MODEL=claude-sonnet-4-6` | 运行时切换 |
| 自定义端点 | 设 `ANTHROPIC_BASE_URL` + `ANTHROPIC_MODEL` | 接 Qwen/GLM/DeepSeek 等 |
| 消息前缀路由 | 用户在飞书输入 `/fast ...` 或 `/think ...` | 逐条消息选模型 |

**按 IM 平台路由不同 AI**：

```json
{
  "aiCommand": "claude",
  "platforms": {
    "telegram": { "aiCommand": "codex" },
    "feishu": { "aiCommand": "claude" },
    "qq": { "aiCommand": "codebuddy" }
  }
}
```

**4 层隐私防护**：

| 层 | 机制 | 防什么 |
|----|------|--------|
| 1. Token 物理隔离 | Token 存在项目目录外（不同盘符） | Bot 读取自身凭证 |
| 2. canUseTool 回调 | 拦截每个工具调用，检查路径和命令 | 越权读写文件、环境变量泄露、shell 逃逸 |
| 3. settings.json deny 规则 | 声明式路径白名单/黑名单 | 纵深防御（兜底 canUseTool 的 bug） |
| 4. 群消息 @mention 过滤 | 群聊只响应 @机器人 的消息 | 误触发、刷屏 |

**运维操作**：

```powershell
# 启动（Windows）
.\start.ps1

# 停止
.\stop.ps1       # 或: npx @wu529778790/open-im stop

# 查看状态
.\status.ps1     # 检查 WebSocket 端口 39281/39282

# 重启
.\stop.ps1; Start-Sleep -Seconds 2; .\start.ps1
```

```bash
# 启动（Linux/macOS）
./start.sh
# 后台运行: nohup ./start.sh > bot.log 2>&1 &

# 停止
npx @wu529778790/open-im stop

# 查看状态
pgrep -f "open-im" && echo "运行中" || echo "未运行"
```

**已记录 15 个踩坑经验**（含根因和修复方案），包括：SDK `allowedTools` 绕过 canUseTool、`permissionMode: 'default'` 在 daemon 模式失效、Windows 路径反斜杠问题、OAuth token 过期等。

详细说明和故障排查见 [skills/lark-im/SKILL.md](skills/lark-im/SKILL.md)。

---

### remote-gui — 远程 GUI 操作

**解决的问题**：Claude Code 无法操作远程服务器上的 GUI 应用。

**工作原理**：

```
┌─────────────────────────────────────────────────┐
│              远程服务器（无显示器）                 │
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

**操作命令参考**：

| 操作 | 命令 | 示例 |
|------|------|------|
| 移动鼠标 | `xdotool mousemove X Y` | `xdotool mousemove 640 330` |
| 左键点击 | `xdotool click 1` | 点击当前位置 |
| 输入文字 | `xdotool type 'text'` | `xdotool type 'user@email.com'` |
| 按键 | `xdotool key <key>` | `xdotool key Return` |
| 组合键 | `xdotool key ctrl+a` | 全选 |
| 截图 | `scrot /tmp/screen.png` | 保存当前画面 |

详细说明和故障排查见 [skills/remote-gui/SKILL.md](skills/remote-gui/SKILL.md)。

### ssh-persist — SSH 持久化连接

**解决的问题**：SSH 连接慢（每次输密码）、频繁断连、被 fail2ban 封禁。

**使用前后对比**：

| 指标 | 之前 | 之后 |
|------|------|------|
| 认证方式 | 密码（慢，触发 fail2ban） | SSH 密钥（即时，安全） |
| 连接命令 | `ssh user@100.100.203.100` | `ssh l40` |
| 心跳保活 | 无（空闲断连） | 每 15 秒 |
| 连接速度 | ~10-30 秒 | ~3-4 秒 |

详细说明和故障排查见 [skills/ssh-persist/SKILL.md](skills/ssh-persist/SKILL.md)。

### tailscale-mesh — Tailscale 跨平台组网

**解决的问题**：不同平台（Windows/macOS/Linux）之间的设备需要互相 SSH 访问，设备可能在 NAT/防火墙后面。

**跨平台 SSH 互通方案**：

| 从 ＼ 到 | Linux | macOS | Windows |
|---------|-------|-------|---------|
| **Linux** | Tailscale SSH 或 OpenSSH | Tailscale SSH | OpenSSH Server |
| **macOS** | Tailscale SSH 或 OpenSSH | Tailscale SSH | OpenSSH Server |
| **Windows** | OpenSSH | OpenSSH | OpenSSH |

> **注意**：Windows 不支持 Tailscale SSH 作为服务端，必须启用 OpenSSH Server。

详细说明和故障排查见 [skills/tailscale-mesh/SKILL.md](skills/tailscale-mesh/SKILL.md)。

## 添加新技能

每个技能是 `skills/` 下的一个目录：

```
skills/my-skill/
├── SKILL.md          # 技能定义（必须，Claude Code 读取）
└── scripts/          # 辅助脚本（可选）
```

欢迎提交 PR 添加新技能或改进现有技能。

## 贡献者

- **Jope Miler** ([@18798aa12](https://github.com/18798aa12)) — Author
- **Claude** (Anthropic) — Co-developer

## 许可证

MIT License — 详见 [LICENSE](LICENSE)
