---
name: lark-im
description: Bridge Lark/Feishu to Claude Code with model switching, privacy isolation, and tool-level access control via patch-package
author: Zhou Qishun, Claude
version: 1.0.0
tags: [lark, feishu, bot, claude, bridge, privacy, model-switch, im]
---

# Lark-IM: Feishu-Claude Bot Bridge

Bridge [Lark/Feishu](https://www.feishu.cn/) instant messaging to [Claude Code](https://claude.ai/code), turning any Feishu chat into an AI-powered coding assistant with full tool access and multi-layer privacy protection.

## When to use

- Want to chat with Claude Code through Feishu (Lark) instead of terminal
- Need to expose Claude Code tools (file read/write, bash, web search) to a Feishu bot safely
- Need fine-grained privacy control: restrict which files the bot can access/modify
- Want to switch the underlying Claude model (Opus, Sonnet, Haiku) without redeploying

## Architecture

```
Feishu User (mobile/desktop)
    │
    ↓  WebSocket (im.message.receive_v1)
    │
┌───────────────────────────────┐
│  @wu529778790/open-im         │  Feishu ↔ Claude bridge (npm)
│  + patch-package patch        │  Injects canUseTool callback
└───────────┬───────────────────┘
            │
            ↓
┌───────────────────────────────┐
│  Claude Agent SDK (V2 Session)│
│  Model: configurable          │  claude-opus-4-5 / sonnet-4 / ...
│  Mode: acceptEdits            │  Auto-approve within canUseTool rules
│  canUseTool: path isolation   │
└───────────┬───────────────────┘
            │
    ┌───────┴────────┐
    ↓                ↓
 MCP Servers      Tools (filtered)
 (context7,       (Bash, Read, Write,
  memory, etc.)    Edit, Glob, Grep)
```

## Setup Guide

### Prerequisites

- Node.js >= 20
- A Feishu app with Bot capability (App ID + App Secret)
- Claude Code OAuth token (subscription or API key)
- Windows / macOS / Linux

### Step 1: Create project

```bash
mkdir larkagent && cd larkagent
npm init -y
```

Edit `package.json`:

```json
{
  "name": "larkagent",
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

## Switching the Underlying Model

The model is configured in the patched `claude-sdk-adapter.js`. There are two approaches:

### Approach A: Change the default in patch (permanent)

In the patch file, modify this line:

```javascript
// Before
model: model || 'claude-opus-4-5',

// After (e.g., switch to Sonnet for cost savings)
model: model || 'claude-sonnet-4-6',
```

Available models:
| Model | ID | Best for |
|-------|----|----------|
| Opus 4.6 | `claude-opus-4-6` | Deepest reasoning, complex tasks |
| Opus 4.5 | `claude-opus-4-5` | Strong reasoning |
| Sonnet 4.6 | `claude-sonnet-4-6` | Best coding model, cost-effective |
| Haiku 4.5 | `claude-haiku-4-5-20251001` | Fast, lightweight tasks |

After changing, re-apply the patch:

```bash
npx patch-package
# Then restart the bot
```

### Approach B: Environment variable override (runtime)

Add model selection to your startup script:

```powershell
# start.ps1 — add before the npx line:
$env:CLAUDE_MODEL = "claude-sonnet-4-6"
```

Then modify the patch to read from env:

```javascript
model: model || process.env.CLAUDE_MODEL || 'claude-opus-4-5',
```

This lets you switch models without touching the patch file.

### Approach C: Per-message model routing (advanced)

For routing different messages to different models (e.g., simple questions to Haiku, complex ones to Opus), modify the event handler to parse a prefix:

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

## Troubleshooting

| Problem | Solution |
|---------|----------|
| Bot doesn't respond | Check WebSocket connection; verify Feishu app events are subscribed |
| "token file not found" | Run `claude setup-token` or manually create `~/.open-im/token` |
| Bot reads files outside project | Verify `canUseTool` path checks; check `settings.json` deny rules |
| Bot exposes env vars | Ensure `printenv`, `echo $*`, `process.env` are in the blocked list |
| Patch not applied after npm install | Verify `"postinstall": "patch-package"` in package.json |
| Group chat spam | Ensure the @mention filter patch is applied in `event-handler.js` |
| Model too slow/expensive | Switch to Sonnet or Haiku (see [Switching the Underlying Model](#switching-the-underlying-model)) |
| "permissionMode" errors | Use `acceptEdits` with `canUseTool`; do not use `settingSources` (V2 limitation) |

## Key Dependencies

| Package | Version | Role |
|---------|---------|------|
| `@wu529778790/open-im` | ^1.8.0 | Feishu WebSocket ↔ Claude bridge |
| `@anthropic-ai/claude-agent-sdk` | ^0.2.83 | Claude V2 Session API |
| `ws` | ^8.20.0 | WebSocket client |
| `patch-package` | ^8.0.1 | Persist canUseTool patch across npm install |
