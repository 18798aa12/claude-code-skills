---
name: lark-im
description: Bridge IM platforms (Feishu/Telegram/QQ/DingTalk/WeCom/WeChat) to AI coding assistants (Claude/Codex/CodeBuddy) with model switching, privacy isolation, and tool-level access control
author: Zhou Qishun, Claude
version: 1.1.0
tags: [lark, feishu, telegram, qq, dingtalk, bot, claude, codex, codebuddy, bridge, privacy, model-switch, im]
---

# Lark-IM: Multi-Platform IM ↔ AI Coding Assistant Bridge

Bridge IM platforms ([Feishu](https://www.feishu.cn/)/Telegram/QQ/DingTalk/WeCom/WeChat) to AI coding assistants ([Claude Code](https://claude.ai/code)/[Codex](https://openai.com/codex)/[CodeBuddy](https://codebuddy.tencent.com/)), turning any chat into an AI-powered coding assistant with full tool access and multi-layer privacy protection.

## When to use

- Want to chat with an AI coding assistant through IM (Feishu, Telegram, QQ, etc.) instead of terminal
- Need to expose AI tools (file read/write, bash, web search) to a bot safely
- Need fine-grained privacy control: restrict which files the bot can access/modify
- Want to switch the underlying AI model or provider without redeploying

## Supported Platforms

### IM Platforms

| Platform | Connection | Status |
|----------|-----------|--------|
| **Feishu/Lark** | WebSocket | Fully supported |
| **Telegram** | Bot API | Fully supported |
| **QQ** | Bot API | Supported |
| **DingTalk** | WebSocket | Supported |
| **WeCom** | WebSocket | Supported |
| **WeChat** | Bridge | Supported |

### AI Backends

| Backend | Provider | Models | Auth Method |
|---------|----------|--------|------------|
| **Claude** (native) | Anthropic | Opus 4.6, Opus 4.5, Sonnet 4.6, Haiku 4.5 | OAuth token / API key |
| **Claude** (custom endpoint) | Any OpenAI-compatible API | Qwen, GLM-4, DeepSeek, etc. | `ANTHROPIC_BASE_URL` + `ANTHROPIC_AUTH_TOKEN` + `ANTHROPIC_MODEL` |
| **Codex** | OpenAI | GPT-4o, o3, etc. via Codex CLI | `OPENAI_API_KEY` / interactive login |
| **CodeBuddy** | Tencent | Tencent AI models via CLI | `CODEBUDDY_API_KEY` / interactive login |

**Custom endpoint support** means you can use **any model** that provides an OpenAI-compatible API (Qwen, GLM, DeepSeek, Llama, Mistral, etc.) by setting `ANTHROPIC_BASE_URL` and `ANTHROPIC_MODEL`.

Each IM platform can be routed to a different AI backend (see [Per-Platform Routing](#per-platform-ai-routing)).

## Architecture

```
IM Users (Feishu / Telegram / QQ / DingTalk / WeCom / WeChat)
    │
    ↓  WebSocket / Bot API
    │
┌───────────────────────────────┐
│  @wu529778790/open-im         │  Multi-IM ↔ Multi-AI bridge
│  + patch-package patch        │  Injects canUseTool callback
└───────────┬───────────────────┘
            │
    ┌───────┼────────┐
    ↓       ↓        ↓
┌────────┐┌────────┐┌──────────┐
│ Claude ││ Codex  ││CodeBuddy │  AI Adapters (selectable)
│  SDK   ││  CLI   ││   CLI    │
└───┬────┘└───┬────┘└────┬─────┘
    │         │          │
    ↓         ↓          ↓
 MCP Servers + Tools (filtered by canUseTool)
```

## Setup Guide

### Prerequisites

- Node.js >= 20
- A Feishu app with Bot capability (App ID + App Secret)
- Claude Code OAuth token (subscription or API key)
- Windows / macOS / Linux

### Step 1: Create project

```bash
mkdir my-im-bot && cd my-im-bot
npm init -y
```

Edit `package.json`:

```json
{
  "name": "my-im-bot",
  "type": "module",
  "scripts": {
    "start": "node src/index.js",
    "postinstall": "patch-package"
  },
  "dependencies": {
    "@anthropic-ai/claude-agent-sdk": "^0.2.83",
    "@wu529778790/open-im": "^1.8.0",
    "ws": "^8.20.0"
  },
  "devDependencies": {
    "patch-package": "^8.0.1"
  }
}
```

```bash
npm install
```

### Step 2: Configure Feishu app

1. Go to [Feishu Open Platform](https://open.feishu.cn/app)
2. Create an app, enable **Bot** capability
3. Subscribe to events: `im.message.receive_v1`, `card.action.trigger`
4. Connection mode: **WebSocket** (long-polling)
5. Save App ID and App Secret

Create config file (store OUTSIDE the project directory for security):

```bash
# Linux/macOS
mkdir -p ~/.open-im
cat > ~/.open-im/config.json << 'EOF'
{
  "appId": "cli_your_app_id",
  "appSecret": "your_app_secret"
}
EOF

# Windows (PowerShell)
New-Item -ItemType Directory -Path "$env:USERPROFILE\.open-im" -Force
# Then create config.json in that directory
```

### Step 3: Store OAuth token securely

```bash
# The token must be stored OUTSIDE the project directory
# so the bot cannot read it at runtime

# Linux/macOS
echo "your-oauth-token" > ~/.open-im/token

# Windows (PowerShell)
"your-oauth-token" | Set-Content "$env:USERPROFILE\.open-im\token"
```

### Step 4: Create startup script

**Windows (start.ps1)**:

```powershell
$tokenFile = "$env:USERPROFILE\.open-im\token"
if (-not (Test-Path $tokenFile)) {
    Write-Host "Error: token file not found at $tokenFile" -ForegroundColor Red
    exit 1
}
$env:CLAUDE_CODE_OAUTH_TOKEN = (Get-Content $tokenFile -Raw).Trim()
$env:CLAUDE_CODE_GIT_BASH_PATH = "D:\Program Files\Git\bin\bash.exe"

Write-Host "Starting Feishu-Claude bridge..." -ForegroundColor Green
npx @wu529778790/open-im start
```

**Linux/macOS (start.sh)**:

```bash
#!/bin/bash
TOKEN_FILE="$HOME/.open-im/token"
if [ ! -f "$TOKEN_FILE" ]; then
    echo "Error: token file not found at $TOKEN_FILE"
    exit 1
fi
export CLAUDE_CODE_OAUTH_TOKEN=$(cat "$TOKEN_FILE" | tr -d '\n')

echo "Starting Feishu-Claude bridge..."
npx @wu529778790/open-im start
```

### Step 5: Apply the privacy patch

Create `patches/@wu529778790+open-im+1.8.0.patch` (see [Privacy Patch](#privacy-patch-canusertool) section below for the full patch).

Then run:

```bash
npx patch-package  # auto-applied on npm install via postinstall hook
```

---

## Switching the Underlying AI Backend & Model

### Backend Selection via config.json

The `~/.open-im/config.json` controls which AI backend to use:

```json
{
  "appId": "your_feishu_app_id",
  "appSecret": "your_feishu_app_secret",
  "aiCommand": "claude",
  "tools": {
    "claude": {
      "env": {
        "ANTHROPIC_MODEL": "claude-opus-4-5"
      }
    },
    "codex": {
      "cliPath": "codex",
      "timeoutMs": 600000
    },
    "codebuddy": {
      "cliPath": "codebuddy",
      "timeoutMs": 600000
    }
  }
}
```

Change `"aiCommand"` to switch the entire backend:
- `"claude"` — Anthropic Claude (default)
- `"codex"` — OpenAI Codex
- `"codebuddy"` — Tencent CodeBuddy

### Per-Platform AI Routing

Route different IM platforms to different AI backends:

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

### Claude Model Switching

#### Available Claude models

| Model | ID | Best for |
|-------|----|----------|
| Opus 4.6 | `claude-opus-4-6` | Deepest reasoning, complex tasks |
| Opus 4.5 | `claude-opus-4-5` | Strong reasoning |
| Sonnet 4.6 | `claude-sonnet-4-6` | Best coding model, cost-effective |
| Haiku 4.5 | `claude-haiku-4-5-20251001` | Fast, lightweight tasks |

#### Approach A: Change the default in patch (permanent)

In the patch file, modify this line:

```javascript
// Before
model: model || 'claude-opus-4-5',

// After (e.g., switch to Sonnet for cost savings)
model: model || 'claude-sonnet-4-6',
```

After changing, re-apply the patch:

```bash
npx patch-package
# Then restart the bot
```

#### Approach B: Environment variable override (runtime)

Add model selection to your startup script:

```powershell
# start.ps1 — add before the npx line:
$env:ANTHROPIC_MODEL = "claude-sonnet-4-6"
```

Or in config.json:

```json
{
  "tools": {
    "claude": {
      "env": { "ANTHROPIC_MODEL": "claude-sonnet-4-6" }
    }
  }
}
```

#### Approach C: Per-message model routing (advanced)

Users type a prefix in chat to select a model:

```javascript
// In event-handler.js, before creating session:
let selectedModel = 'claude-opus-4-5';  // default
if (content.startsWith('/fast ')) {
    selectedModel = 'claude-haiku-4-5-20251001';
    content = content.replace('/fast ', '');
} else if (content.startsWith('/think ')) {
    selectedModel = 'claude-opus-4-6';
    content = content.replace('/think ', '');
}
```

Users can then type `/fast what is 2+2` in Feishu to use Haiku.

### Using Custom/Third-Party Models (Qwen, GLM, DeepSeek, etc.)

The Claude adapter supports any OpenAI-compatible API endpoint via custom environment variables:

```json
{
  "tools": {
    "claude": {
      "env": {
        "ANTHROPIC_BASE_URL": "https://dashscope.aliyuncs.com/compatible-mode/v1",
        "ANTHROPIC_AUTH_TOKEN": "sk-your-qwen-api-key",
        "ANTHROPIC_MODEL": "qwen3-coder"
      }
    }
  }
}
```

**Tested compatible providers**:

| Provider | Base URL | Model ID Example |
|----------|----------|-----------------|
| **Qwen (DashScope)** | `https://dashscope.aliyuncs.com/compatible-mode/v1` | `qwen3-coder`, `qwen-plus` |
| **GLM (Zhipu AI)** | `https://open.bigmodel.cn/api/paas/v4` | `glm-4`, `glm-4-plus` |
| **DeepSeek** | `https://api.deepseek.com/v1` | `deepseek-chat`, `deepseek-coder` |
| **Moonshot (Kimi)** | `https://api.moonshot.cn/v1` | `moonshot-v1-128k` |
| **Any OpenAI-compatible** | Your endpoint URL | Your model ID |

### Codex (OpenAI) Setup

```bash
# Install Codex CLI
npm install -g @openai/codex

# Auth (one of these):
export OPENAI_API_KEY="sk-..."
# Or: codex login

# Configure in config.json:
{
  "aiCommand": "codex",
  "tools": {
    "codex": {
      "cliPath": "codex",
      "timeoutMs": 600000,
      "proxy": "http://127.0.0.1:7890"
    }
  }
}
```

### CodeBuddy (Tencent) Setup

```bash
# Install CodeBuddy CLI
npm install -g @tencent-ai/codebuddy-code

# Auth (one of these):
export CODEBUDDY_API_KEY="your-key"
# Or: codebuddy login

# Configure in config.json:
{
  "aiCommand": "codebuddy",
  "tools": {
    "codebuddy": {
      "cliPath": "codebuddy",
      "timeoutMs": 600000
    }
  }
}
```

---

## Privacy & Security (4-Layer Protection)

### Layer 1: Token Physical Isolation

OAuth token and Feishu app secret are stored **outside** the project directory (on a different drive on Windows, or in `~/.open-im/` on Linux/macOS). The bot process cannot read these files at runtime.

```
Token flow:
  ~/.open-im/token  →  start.ps1 reads  →  sets env var  →  SDK uses env var
                        (human runs)        (in memory)       (never logged)
```

### Layer 2: canUseTool Callback (Code-Level Enforcement)

The patch injects a `canUseTool` function that intercepts every tool call before execution:

```javascript
async function canUseTool(toolName, input, options) {
    const rawPath = (input.file_path || input.path || '').replace(/\\/g, '/').toLowerCase();

    // Write/Edit — only within allowed subdirectory
    if (['Write', 'Edit', 'NotebookEdit'].includes(toolName)) {
        if (!isInAllowedWriteDir(rawPath)) {
            return { behavior: 'deny', message: 'Write access denied' };
        }
    }

    // Read/Glob/Grep — only within project directory
    if (['Read', 'Glob', 'Grep'].includes(toolName)) {
        if (!isInProjectDir(rawPath)) {
            return { behavior: 'deny', message: 'Read access denied' };
        }
    }

    // Bash — block dangerous commands
    if (toolName === 'Bash') {
        const cmd = (input.command || '').toLowerCase();
        const blocked = [
            'printenv', 'env ',                    // env var leaks
            '$claude_code_oauth', '$anthropic',    // token leaks
            'process.env', 'os.environ',           // programmatic env access
            'git push', 'git remote',              // no upstream pushes
            'powershell', 'pwsh', 'cmd /c',        // shell escape
            'node -e', 'python -c',                // inline code execution
        ];
        for (const b of blocked) {
            if (cmd.includes(b)) {
                return { behavior: 'deny', message: `Blocked: "${b}"` };
            }
        }
    }

    return { behavior: 'allow' };
}
```

### Layer 3: settings.json Declarative Rules (Defense in Depth)

Create `.claude/settings.json` as a second layer of path restrictions:

```json
{
  "permissions": {
    "allow": [
      "Read(<project-dir>/**)",
      "Write(<project-dir>/<writable-subdir>/**)",
      "Edit(<project-dir>/<writable-subdir>/**)",
      "Glob(<project-dir>/**)",
      "Grep(<project-dir>/**)",
      "Bash(ls *)", "Bash(cat *)", "Bash(git status)", "Bash(git log*)"
    ],
    "deny": [
      "Read(C:/**)", "Write(C:/**)", "Edit(C:/**)",
      "Bash(printenv*)", "Bash(env *)", "Bash(echo $*)",
      "Bash(* $CLAUDE_CODE_OAUTH*)", "Bash(* $ANTHROPIC*)",
      "Bash(powershell*)", "Bash(cmd *)",
      "Bash(git push*)", "Bash(git remote*)", "Bash(rm -rf*)"
    ]
  }
}
```

### Layer 4: Group Message Filtering

The patch also ensures the bot only responds to **@mentions** in group chats, preventing accidental triggers:

```javascript
if (chatType === 'group') {
    const mentions = message.mentions;
    const hasBotMention = Array.isArray(mentions) && mentions.length > 0;
    if (!hasBotMention) {
        return;  // Skip non-@mention group messages
    }
}
```

### Security Checklist

Before deploying, verify:

- [ ] Token file is outside the project directory
- [ ] `canUseTool` blocks env var access (`printenv`, `$CLAUDE_CODE_OAUTH`, etc.)
- [ ] `canUseTool` restricts Write/Edit to the intended subdirectory only
- [ ] `canUseTool` blocks shell escape (`powershell`, `cmd /c`, `node -e`, `python -c`)
- [ ] `settings.json` deny list covers all sensitive paths
- [ ] No secrets in CLAUDE.md, package.json, or any committed file
- [ ] `.gitignore` excludes token files, `.open-im/`, `.mcp-data/`
- [ ] Bot cannot `git push` or `git remote add`

---

## Privacy Patch (canUseTool)

The full patch lives in `patches/@wu529778790+open-im+<version>.patch`. It modifies two files:

### 1. `claude-sdk-adapter.js` — adds canUseTool callback

Key changes:
- Injects `canUseTool` function with path isolation logic
- Sets `permissionMode: 'acceptEdits'` (auto-approve edits that pass canUseTool)
- Passes `env: { ...process.env }` so the SDK inherits the OAuth token

### 2. `event-handler.js` — adds group @mention filter

Key changes:
- Reads `chat_type` from message
- Skips group messages without @mention

### Generating the patch

After manually editing the files in `node_modules/@wu529778790/open-im/dist/`:

```bash
npx patch-package @wu529778790/open-im
# Creates patches/@wu529778790+open-im+1.8.0.patch
# Committed to git, auto-applied on npm install
```

---

## MCP Server Configuration

Create `.mcp.json` in the project root to define available MCP servers:

```json
{
  "mcpServers": {
    "context7": {
      "command": "npx",
      "args": ["-y", "@upstash/context7-mcp@latest"]
    },
    "fetch": {
      "command": "npx",
      "args": ["-y", "@modelcontextprotocol/server-fetch"]
    },
    "sequential-thinking": {
      "command": "npx",
      "args": ["-y", "@modelcontextprotocol/server-sequential-thinking"]
    },
    "memory": {
      "command": "npx",
      "args": ["-y", "@modelcontextprotocol/server-memory"],
      "env": {
        "MEMORY_FILE_PATH": "<project-dir>/.mcp-data/memory.json"
      }
    },
    "filesystem": {
      "command": "npx",
      "args": ["-y", "@modelcontextprotocol/server-filesystem", "<project-dir>"]
    },
    "sqlite": {
      "command": "uvx",
      "args": ["mcp-server-sqlite", "--db-path", "<project-dir>/.mcp-data/data.db"]
    }
  }
}
```

All MCP data paths should point within the project directory to maintain isolation.

---

## CLAUDE.md (Bot Instructions)

Create a `CLAUDE.md` in the project root to give the bot its identity and constraints:

```markdown
# My Feishu Bot

## Identity
You are an AI assistant accessed through Feishu, powered by Claude.

## Constraints
- Working directory: <project-dir>/ only
- No push to GitHub, no adding git remotes
- Reply in the same language the user uses

## What you can do
- Read/search/analyze files in the project
- Write/edit files in <writable-subdir>/ only
- Run safe bash commands (ls, cat, grep, git status/log/diff)
- Use MCP tools (web fetch, memory, sequential thinking)
```

---

## Operations: Start / Stop / Status

### Start the bot

**Windows (PowerShell)**:

```powershell
# In the project directory
.\start.ps1
```

`start.ps1` does three things:
1. Reads OAuth token from `~\.open-im\token`
2. Sets `CLAUDE_CODE_OAUTH_TOKEN` and `CLAUDE_CODE_GIT_BASH_PATH` env vars
3. Runs `npx @wu529778790/open-im start` (WebSocket daemon)

**Linux/macOS**:

```bash
chmod +x start.sh
./start.sh

# Or run in background:
nohup ./start.sh > bot.log 2>&1 &
```

### Stop the bot

**Windows (PowerShell)**:

```powershell
.\stop.ps1
# Internally runs: npx @wu529778790/open-im stop
```

**Linux/macOS**:

```bash
npx @wu529778790/open-im stop

# Or if running in background, find and kill:
ps aux | grep open-im | grep -v grep | awk '{print $2}' | xargs kill
```

### Check status

**Windows (PowerShell)** — `status.ps1`:

```powershell
# Checks if the bot's WebSocket ports are occupied
Get-NetTCPConnection -LocalPort 39281,39282 -ErrorAction SilentlyContinue | ForEach-Object {
    $proc = Get-Process -Id $_.OwningProcess -ErrorAction SilentlyContinue
    Write-Host "Port $($_.LocalPort) in use — PID: $($_.OwningProcess) Process: $($proc.Name)" -ForegroundColor Cyan
}
if (-not (Get-NetTCPConnection -LocalPort 39281 -ErrorAction SilentlyContinue)) {
    Write-Host "Service not running" -ForegroundColor Red
}
```

**Linux/macOS**:

```bash
# Check if open-im process is running
pgrep -f "open-im" && echo "Running" || echo "Not running"

# Check port usage
ss -tlnp | grep -E '39281|39282'
```

### Restart

```powershell
# Windows
.\stop.ps1; Start-Sleep -Seconds 2; .\start.ps1

# Linux/macOS
npx @wu529778790/open-im stop && sleep 2 && ./start.sh
```

---

## Known Issues & Solutions (Lessons Learned)

These are real problems encountered during development. The skill documents them so Claude can auto-diagnose and fix them.

### Issue 1: canUseTool bypassed when allowedTools is set

**Symptom**: Bot writes to files outside the allowed directory despite canUseTool checks.

**Root cause**: The Claude Agent SDK pre-approves tools listed in `allowedTools`, completely skipping the `canUseTool` callback.

**Fix**: Never set `allowedTools` in sessionOptions. Let all tool invocations go through canUseTool:

```javascript
const sessionOptions = {
    model: model || 'claude-opus-4-5',
    permissionMode: 'acceptEdits',
    canUseTool,
    // Do NOT set allowedTools — it bypasses canUseTool
    env: { ...process.env },
};
```

### Issue 2: Non-interactive write fails with permissionMode 'default'

**Symptom**: Bot silently fails when trying to write files. No error, no output.

**Root cause**: `permissionMode: 'default'` tries to show interactive permission prompts, which fail in a daemon/bot context with no stdin.

**Fix**: Use `permissionMode: 'acceptEdits'`. The actual path isolation is enforced by canUseTool + settings.json deny rules.

### Issue 3: SDK error "suggested permissions not found in response"

**Symptom**: Writing to allowed directories throws an internal SDK error.

**Root cause**: canUseTool callback returns `{ behavior: 'allow' }` without the `updatedPermissions` field. The SDK expects this field even for allow responses.

**Fix**: Always include `updatedPermissions` in the return:

```javascript
return { behavior: 'allow', updatedPermissions: options.suggestions || [] };
```

### Issue 4: OAuth token lost in daemon mode

**Symptom**: Bot starts but returns authentication errors. Token was set in the parent shell.

**Root cause**: When `npx @wu529778790/open-im start` forks a daemon, the child process may lose parent environment variables.

**Fix**: Explicitly pass `env: { ...process.env }` in sessionOptions so the SDK inherits the OAuth token from the daemon process.

### Issue 5: V2 Session does not support settingSources

**Symptom**: Bot doesn't auto-load CLAUDE.md, skills, or system prompts at session start.

**Root cause**: Claude Agent SDK V2 intentionally removed support for `settingSources`, `cwd`, and `systemPrompt` parameters.

**Workaround**: Instruct the bot in CLAUDE.md to manually read context files on first message. This is a V2 limitation with no fix.

### Issue 6: Relative paths bypass canUseTool on Windows

**Symptom**: Bot writes to project root files (e.g., `CLAUDE.md`) despite canUseTool restricting writes to a subdirectory.

**Root cause**: Relative paths like `./CLAUDE.md` don't get normalized properly. Combined with `acceptEdits`, the operation is approved before path checks can distinguish directories.

**Fix**: Two layers:
1. In canUseTool, normalize all paths: `.replace(/\\/g, '/').toLowerCase()`
2. In settings.json, use explicit deny rules for the broad directory, with specific allow rules for the writable subdirectory:

```json
{
  "deny": ["Write(D:/**)", "Write(/d/**)"],
  "allow": ["Write(D:/mybot/my-project/**)"]
}
```

### Issue 7: patch-package fails after npm update

**Symptom**: `npm install` shows "PATCH FAILED" errors after updating `@wu529778790/open-im`.

**Root cause**: The patch contains exact line numbers. Any change in the target file (even whitespace) causes offset mismatches.

**Fix**: After npm update:
1. Check if patch applies: `npm install`
2. If it fails, manually re-edit the files in `node_modules/`
3. Regenerate: `npx patch-package @wu529778790/open-im`
4. Commit the updated patch file

### Issue 8: Bot responds to all group messages (spam)

**Symptom**: Bot replies to every message in a Feishu group, not just @mentions.

**Root cause**: Event handler processes all `im.message.receive_v1` events without checking the `mentions` array.

**Fix**: Add @mention filter in event-handler.js patch:

```javascript
const chatType = message.chat_type ?? 'p2p';
if (chatType === 'group') {
    const hasBotMention = Array.isArray(message.mentions) && message.mentions.length > 0;
    if (!hasBotMention) return;  // Skip non-@mention messages
}
```

### Issue 9: Bash commands exit with code 1 on Windows (no error output)

**Symptom**: Bash tool calls silently fail on Windows.

**Root cause**: Claude Code defaults to cmd.exe on Windows. Commands like `grep`, `find`, Unix-style paths don't work in cmd.

**Fix**: Set `CLAUDE_CODE_GIT_BASH_PATH` in the startup script:

```powershell
$env:CLAUDE_CODE_GIT_BASH_PATH = "D:\Program Files\Git\bin\bash.exe"
```

### Issue 10: settings.json path matching unreliable on Windows

**Symptom**: Allow/deny rules don't match. `Write(my-project/**)` doesn't catch `my-project\file.txt`.

**Root cause**: Windows backslash paths vs Unix forward slash patterns.

**Fix**: Include both formats in rules:

```json
"allow": [
  "Write(my-project/**)",
  "Write(D:/mybot/my-project/**)",
  "Write(/d/mybot/my-project/**)"
]
```

### Issue 11: New Feishu group doesn't trigger events

**Symptom**: Bot added to a new group but doesn't respond to any messages.

**Root cause**: Feishu event subscriptions are tied to the published app version. Adding new groups or changing permissions requires a new version publication.

**Fix**: Go to Feishu Open Platform → App → Version Management → Publish a new version. Wait for approval.

### Issue 12: OAuth token expires after 1 year

**Symptom**: Bot stops responding. Logs show authentication errors.

**Root cause**: Anthropic OAuth tokens have a 1-year TTL.

**Fix**: Regenerate before expiration:

```powershell
# Generate new token
claude setup-token
# Update stored token
Set-Content $env:USERPROFILE\.open-im\token "new-token-here"
# Restart bot
.\stop.ps1; .\start.ps1
```

### Issue 13: "No API credentials" warning in logs (false alarm)

**Symptom**: Logs show `"No API credentials found"` but bot works fine.

**Root cause**: The open-im library tries to auto-detect credentials and warns if not found. The actual token is passed via `env: { ...process.env }`, which the auto-detection doesn't check.

**Fix**: Safe to ignore. This is a cosmetic warning, not a functional problem.

### Issue 14: bypassPermissions disables ALL security checks

**Symptom**: Setting `permissionMode: 'bypassPermissions'` makes canUseTool and settings.json rules completely non-functional.

**Root cause**: By design, `bypassPermissions` skips all permission layers including canUseTool.

**Fix**: Never use `bypassPermissions`. Always use `acceptEdits` (for bot/daemon) or `default` (for interactive CLI).

### Issue 15: @wu529778790/open-im vs claude-to-im confusion

**Symptom**: Searching for Feishu-Claude bridge libraries returns `op7418/claude-to-im`, which is not published to npm.

**Root cause**: Two different projects with similar goals. `claude-to-im` (op7418) is a private/unreleased package.

**Fix**: Use `@wu529778790/open-im` (npm published, actively maintained). This is the correct library.

---

## Critical Rules (Quick Reference)

| Rule | Why |
|------|-----|
| Never set `allowedTools` | It bypasses canUseTool completely |
| Always use `acceptEdits`, not `default` | `default` requires interactive stdin |
| Always return `updatedPermissions` in canUseTool | SDK crashes without it |
| Always pass `env: { ...process.env }` | OAuth token gets lost in daemon fork |
| Always normalize paths in canUseTool | Windows backslashes break matching |
| Include both `/` and `\` path formats in settings.json | Windows path inconsistency |
| Never use `bypassPermissions` | Disables ALL security layers |
| Re-patch after npm update | Line offsets may shift |
| Republish Feishu app after permission changes | Events are version-tied |
| Renew OAuth token before 1-year expiry | Token silently expires |

---

## Key Dependencies

| Package | Version | Role |
|---------|---------|------|
| `@wu529778790/open-im` | ^1.8.0 | Feishu WebSocket ↔ Claude bridge |
| `@anthropic-ai/claude-agent-sdk` | ^0.2.83 | Claude V2 Session API |
| `ws` | ^8.20.0 | WebSocket client |
| `patch-package` | ^8.0.1 | Persist canUseTool patch across npm install |
