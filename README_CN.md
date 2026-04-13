# Claude Code 技能合集

[English](README.md) | **中文**

一个持续增长的 [Claude Code](https://claude.ai/code) 自定义技能集合。覆盖 Cloudflare 部署、网络/代理管理、macOS 自动化、远程服务器操作和 IM 平台桥接。

## 可用技能

### Cloudflare

| 技能 | 描述 | 使用场景 |
|------|------|---------|
| [cf-pages-deploy](skills/cloudflare/cf-pages-deploy/) | Cloudflare Pages 部署，自动修复 1101 错误 | 部署 Web 应用和代理服务，理解 Pages vs Workers 取舍 |
| [cloudflare-tunnel](skills/cloudflare/cloudflare-tunnel/) | cloudflared 隧道搭建 + WebSocket 4 大坑修复 | 暴露本地服务、修复 WebSocket 不稳定、多服务隧道 |
| [cf-auto-checkin](skills/cloudflare/cf-auto-checkin/) | 自动签到 Worker + TG 通知，两种登录模式 | 每日自动签到、Cookie/API 登录、Cron 定时、多目标 TG 推送 |

### 网络

| 技能 | 描述 | 使用场景 |
|------|------|---------|
| [ssh-persist](skills/networking/ssh-persist/) | 自动部署 SSH 密钥和持久化连接管理 | 免密码登录、防断连、加速 SSH 连接 |
| [tailscale-mesh](skills/networking/tailscale-mesh/) | Tailscale 组网：跨平台 SSH、出口节点、设备管理 | Windows/macOS/Linux 互相 SSH、通过出口节点访问外网 |
| [proxy-multi-platform](skills/networking/proxy-multi-platform/) | 三平台代理配置管理（QX/Surge/Clash），20+ 事故教训 | 跨平台同步配置、DNS 路由、策略组管理 |
| [vps-singbox](skills/networking/vps-singbox/) | VPS sing-box 5 协议代理服务器，13 节点生产经验 | 部署 VLESS Reality、Hysteria2、TUIC、Trojan + CDN 中转 |

### 自动化

| 技能 | 描述 | 使用场景 |
|------|------|---------|
| [remote-gui](skills/automation/remote-gui/) | 通过 SSH 在无显示器的 Linux 服务器上操作 GUI 应用 | 在 GPU 服务器上启动桌面程序、点击按钮、填写表单 |
| [macos-accessibility](skills/automation/macos-accessibility/) | macOS Accessibility API 自动化 + 三层回退策略 | 构建控制 Mac 应用的 AI Agent、处理中文输入、AX API 失败 |

### 通讯

| 技能 | 描述 | 使用场景 |
|------|------|---------|
| [lark-im](skills/messaging/lark-im/) | 多 IM 平台接入多 AI 后端：底模切换 + 4 层隐私隔离 | 飞书/Telegram/QQ 等接入 Claude/Codex/Qwen/GLM 等 |

---

## 快速开始（5 分钟）

```bash
# 1. 克隆仓库
git clone https://github.com/18798aa12/claude-code-skills.git
cd claude-code-skills

# 2. 按分类安装技能
cp -r skills/cloudflare/* ~/.claude/skills/       # Cloudflare 技能
cp -r skills/networking/* ~/.claude/skills/        # 网络技能
cp -r skills/automation/* ~/.claude/skills/        # 自动化技能
cp -r skills/messaging/* ~/.claude/skills/         # 通讯技能

# 或安装特定技能
cp -r skills/networking/vps-singbox ~/.claude/skills/
cp -r skills/cloudflare/cf-pages-deploy ~/.claude/skills/

# 3. 在 Claude Code 中使用
# 直接描述你的需求，Claude 会自动选择合适的技能：
#   "帮我把应用部署到 Cloudflare Pages"
#   "在 VPS 上搭建 sing-box，配置 VLESS 和 Hysteria2"
#   "同步我的 QX、Surge、Clash 代理配置"
#   "构建一个能控制桌面应用的 macOS Agent"
```

## 前提条件

- 已安装 [Claude Code](https://claude.ai/code) CLI
- （网络技能）SSH 访问远程服务器
- （Cloudflare 技能）Cloudflare 账号和 API Token
- （lark-im）Node.js >= 20，IM 平台 Bot 凭证
- （macos-accessibility）macOS 14+，Xcode，辅助功能权限
- （可选）[Tailscale](https://tailscale.com/) 账号

## 技能特色

### 每个技能都包含

- **何时使用** — 明确的触发条件
- **自动搭建流程** — 逐步自动化设置
- **自动修复** — 常见故障自动解决方案
- **故障排除** — 边缘情况的详细诊断
- **生产教训** — 真实事故中总结的经验

### 实战验证的知识

这些技能编码了以下真实经验：
- **20+ 次代理配置事故** → proxy-multi-platform
- **8 个国家 13 个 VPS 节点** → vps-singbox
- **4 个 WebSocket 部署陷阱** → cloudflare-tunnel
- **Workers 1101 封锁** → cf-pages-deploy
- **macOS AX API 故障** → macos-accessibility
- **15+ 次 Agent 安全事故** → proxy-multi-platform
- **5 种 Cookie 解析策略** → cf-auto-checkin

## 贡献

欢迎 PR！技能按分类组织在 `skills/` 下：

```
skills/
├── cloudflare/          # Cloudflare 生态
│   ├── cf-pages-deploy/
│   ├── cloudflare-tunnel/
│   └── cf-auto-checkin/
├── networking/          # 网络与连接
│   ├── ssh-persist/
│   ├── tailscale-mesh/
│   ├── proxy-multi-platform/
│   └── vps-singbox/
├── automation/          # 自动化工具
│   ├── remote-gui/
│   └── macos-accessibility/
└── messaging/           # 通讯集成
    └── lark-im/
```

每个技能目录必须包含 `SKILL.md` 文件和 frontmatter：

```yaml
---
name: my-skill
description: 一行描述
author: 作者
version: 1.0.0
tags: [相关, 标签]
---
```

## 贡献者

- **Jope Miler** ([@18798aa12](https://github.com/18798aa12)) — 作者
- **Claude** (Anthropic) — 协作开发

## 许可证

MIT License — 详见 [LICENSE](LICENSE)
