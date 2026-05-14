---
name: claude-code-statusline
description: 2-line Claude Code statusline showing real-time 5h/7d Anthropic plan usage % + reset times, scraped directly from claude.ai dashboard API. Defeats Cloudflare + region-block + auto-rotates session via Chrome cookies. Falls back to ccusage USD estimation when Chrome not available.
author: Jope Miler, Claude
version: 1.0.0
tags: [claude-code, statusline, monitoring, anthropic, rate-limit, ccusage, sessionkey, scraping, macos]
---

# Claude Code Statusline — Real Plan Usage Monitor

A 2-line statusline that shows **the same data as your claude.ai/settings/billing dashboard** — directly inside your terminal. Shows accurate 5h session %, 7d weekly %, exact reset times, plus token I/O and cost.

```
user@~/path  ⎇ branch*  Opus 4.7  HH:MM  🧠 ctx%  ✓ todos
⚡5h✓ ▰▰▱▱▱ 45% $40  · ↻02:50(剩2h08m) · ↓61M↑154k │ 📅7d✓ ▰▰▱▱▱ 54% $57 · ↻05-15 11:00(剩10h17m) · ↓80M↑218k · Σ80M
```

The `✓` mark = real Anthropic dashboard data. `≈` = ccusage USD estimation (fallback when scrape unavailable).

## When to use

- You hit "weekly limit reached" surprises and want a real-time burn-down indicator
- ccusage's USD estimation is wildly off your actual Anthropic quota (e.g., 80% estimate vs 43% real)
- You want exact reset times (not relative `4h left`) so you can plan your work
- You want it visible in **every** Claude Code session globally, no per-project setup

## Prerequisites

```bash
# 1. ccusage (auto-installed via npx)
which npx  # need Node.js + npm

# 2. Python deps for live scrape (optional, for ✓ real data)
pip install tls-client pycookiecheat pyyaml

# 3. jq (statusline parses JSON input from Claude Code)
brew install jq

# 4. Chrome browser logged into claude.ai (for sessionKey auto-rotation)
#    — Brave / Edge / Arc all work too (Chromium-based)

# 5. Local HTTP proxy if your region is blocked from claude.ai/api
#    — claude.ai/api has region-blocking. From blocked regions you need a proxy.
#    — Default: tries 127.0.0.1:6152 (Surge), 127.0.0.1:7890 (mihomo/Clash)
```

## Why claude.ai scrape (not ccusage USD)?

Anthropic's [GitHub issue #32796](https://github.com/anthropics/claude-code/issues/32796) requests an official rate-limit query API. Not implemented as of 2026-05.

**ccusage estimates by reverse-engineering API list price × tokens used. This is wildly inaccurate vs Anthropic's real internal quota algorithm.**

Real-world example (Max 5x plan, same moment):
| Metric | ccusage USD estimate | Anthropic dashboard | Δ |
|--------|---------------------|--------------------|----|
| 5h % | 80% | 43% | +37 pts ❌ |
| 7d % | 17% | 53% | -36 pts ❌ |
| 5h reset | 04:00 | 02:50 | +1h10m ❌ |
| 7d reset | 05-17 16:00 | today 11:00 | +2 days ❌ |

The only way to get accurate numbers is to query the same endpoint that powers `claude.ai/settings/billing`:

```
GET https://claude.ai/api/organizations/<org_uuid>/usage
→ { "five_hour": {"utilization": 45.0, "resets_at": "ISO_TIMESTAMP"},
    "seven_day": {"utilization": 54.0, "resets_at": "..."},
    "seven_day_sonnet": {...} }
```

## Architecture (two background daemons)

```
┌──────────────────────────────────────────────────────────────┐
│ Claude Code calls statusline.sh on every refresh             │
│   - reads cache files (instant, <100ms)                      │
│   - prints 2 lines, never blocks                             │
└──────────────┬───────────────────────────────────────────────┘
               ↓
   /tmp/cc-statusline-cache/
       ├── usage.env       ← ccusage data (token in/out, cost)
       └── real-usage.env  ← claude.ai scrape (real %, reset_at)
               ↑
   Two launchd daemons (60s, RunAtLoad):
       1. com.claude.refresh-usage  → npx ccusage blocks/daily/weekly
       2. com.claude.fetch-real-usage → claude.ai/api/.../usage scrape
```

### Why two daemons?

ccusage scans all transcript JSONLs (~30s on a heavy user). Cannot block statusline. Scrape is cheap (~1s) but needs proxy + browser cookies. Both run independently; statusline reads cache.

## Three Cloudflare bypass tricks

claude.ai blocks naive `curl` with multiple defenses. The scrape script defeats all three:

### 1. Region block (302 → app-unavailable-in-region)

`claude.ai/api/*` checks request IP. From China/Russia/etc., redirects to `https://www.anthropic.com/app-unavailable-in-region` even with valid session.

**Fix**: route through a local HTTP proxy with overseas exit (Surge/mihomo). The script auto-tries `127.0.0.1:6152` and `127.0.0.1:7890`.

### 2. Cloudflare TLS fingerprint check (403 + "Just a moment...")

Vanilla `curl` and Python `requests` get challenged because their TLS handshake doesn't look like a browser.

**Fix**: `tls-client` Python lib with `client_identifier="chrome_120"` mimics Chrome's exact TLS Client Hello. Combined with `cf_clearance` cookie (auto-extracted from Chrome), Cloudflare lets the request through.

### 3. sessionKey 30-day expiry (401 unauthorized)

The cookie `sessionKey` (`sk-ant-sid01-...`) expires every ~30 days. Manually re-copying is annoying.

**Fix**: read directly from Chrome's local cookie SQLite database via `pycookiecheat`. As long as you stay logged in via browser, Anthropic auto-rotates the cookie and Chrome auto-receives the new one — script always reads the freshest.

Multi-browser fallback chain: Chrome → Brave → Edge → Arc → manual `SESSION_KEY` in conf.

## Installation

```bash
# 1. Copy scripts to ~/.claude/
cp statusline.sh refresh-usage.sh fetch-real-usage.sh ~/.claude/
cp statusline.conf.example ~/.claude/statusline.conf
chmod +x ~/.claude/{statusline,refresh-usage,fetch-real-usage}.sh
chmod 600 ~/.claude/statusline.conf

# 2. Auto-detect your org UUID + plan tier from OAuth token (one-time)
~/.claude/statusline-setup.sh

# 3. Wire up statusLine in ~/.claude/settings.json
# (manually add this stanza, or run: claude config set statusLine ...)
{
  "statusLine": {
    "type": "command",
    "command": "/Users/$USER/.claude/statusline.sh",
    "padding": 0
  }
}

# 4. Install launchd daemons (60s background refresh)
cp com.claude.refresh-usage.plist ~/Library/LaunchAgents/
cp com.claude.fetch-real-usage.plist ~/Library/LaunchAgents/
launchctl load ~/Library/LaunchAgents/com.claude.{refresh,fetch-real}-usage.plist

# 5. Restart Claude Code (cmd+Q + reopen)
```

## Files

| File | Purpose | When it runs |
|------|---------|--------------|
| `statusline.sh` | Display script (reads cache, prints 2 lines) | Every Claude Code refresh, <100ms |
| `refresh-usage.sh` | Wraps `ccusage blocks/daily/weekly` → cache | launchd 60s |
| `fetch-real-usage.sh` | Scrapes `claude.ai/api/.../usage` → cache | launchd 60s |
| `statusline.conf.example` | Config: plan tier, optional manual sessionKey | Read by all 3 scripts |
| `com.claude.refresh-usage.plist` | LaunchAgent for ccusage | macOS init |
| `com.claude.fetch-real-usage.plist` | LaunchAgent for scrape | macOS init |
| `statusline-setup.sh` | One-time setup: detect org UUID, find proxy port | Manual run |

## Configuration: `~/.claude/statusline.conf`

```bash
# Your Anthropic plan (only used as fallback if scrape fails)
#   pro    — $20/mo  — 5h~$8,   7d~$50
#   max5   — $100/mo — 5h~$40,  7d~$280
#   max20  — $200/mo — 5h~$160, 7d~$1120
CC_PLAN=max5

# Manual sessionKey FALLBACK (usually leave empty — scripts read live from Chrome)
# Only fill this if no Chromium browser is installed.
SESSION_KEY=""

# Your org UUID (auto-detected on first run, override here if multiple orgs)
ORG_UUID=""
```

## Display anatomy

**Line 1 (basic context)**:
```
user@~/path  ⎇ branch*  Opus 4.7  HH:MM  🧠 ctx_pct%  ✓ todos
```

| Field | Source | Color |
|-------|--------|-------|
| `user@path` | `whoami` + cwd from input JSON | cyan + blue |
| `⎇ branch*` | `git rev-parse` (only if cwd is git repo) | green + yellow `*` if dirty |
| `Opus 4.7` | input JSON `model.display_name` | gray |
| `HH:MM` | `date +%H:%M` | dim white |
| `🧠 N%` | input JSON `context_window.remaining_percentage` | green/yellow/red by value |
| `✓ N` | grep todos in transcript tail | cyan |

**Line 2 (usage)**:
```
⚡5h✓ ▰▰▱▱▱ 47% $42 · ↻02:50(剩2h04m) · ↓64M↑168k │ 📅7d✓ ▰▰▱▱▱ 54% $58 · ↻05-15 11:00(剩10h14m) · ↓83M↑225k · Σ83M
```

| Field | Source | Notes |
|-------|--------|-------|
| `⚡5h✓` | scrape `/usage.five_hour` | `✓` real, `≈` estimate |
| `▰▰▱▱▱ 47%` | utilization | bar (5 segs × 20%); green/yellow/red |
| `$42` | ccusage cost in current 5h block | reference only |
| `↻02:50` | scrape `resets_at` ISO → local clock | exact wall-clock time |
| `(剩2h04m)` | computed live every render | second-precision countdown |
| `↓64M↑168k` | ccusage token counts (in/out) | accurate (not estimate) |
| `📅7d` | same fields, weekly window | |
| `Σ83M` | total tokens (in+out+cache) | |

## Color thresholds

| Field | Green | Yellow | Red |
|-------|-------|--------|-----|
| 5h % | <50% | 50-80% | >80% |
| 7d % | <50% | 50-80% | >80% |
| ctx % | >50% | 20-50% | <20% |

## Troubleshooting

### Statusline shows `≈` instead of `✓`

scrape failed. Check `~/Library/Logs/claude-fetch-real-usage.log`:

- **`HTTP 302 → app-unavailable-in-region`**: proxy not running or wrong exit country
- **`HTTP 403 + "Just a moment..."`**: Cloudflare challenge, missing `cf_clearance` cookie → visit claude.ai in Chrome once
- **`no sessionKey in Chrome cookies`**: not logged in, or wrong Chromium browser → log in to claude.ai
- **`HTTP 401`**: sessionKey expired → visit claude.ai once, Chrome auto-receives new cookie

### Statusline takes >1 second

Should be <100ms after first cache populates. If slow:
- transcript JSONL is huge → `grep` on tail-1MB only (scripts already do this)
- Chrome cookie DB locked (Chrome currently running) → `pycookiecheat` handles this, but check write permissions

### Wrong org / multi-org accounts

`fetch-real-usage.sh` auto-detects org from `lastActiveOrg` cookie. If you have multiple orgs:
- Set `ORG_UUID="..."` in `statusline.conf`
- Or switch active org in claude.ai UI; cookie updates automatically

### Mac sleep / Surge restart

LaunchAgents `RunAtLoad=true` + 60s interval. After wake, next refresh within 60s. If stale data persists:
```bash
launchctl unload ~/Library/LaunchAgents/com.claude.fetch-real-usage.plist
launchctl load ~/Library/LaunchAgents/com.claude.fetch-real-usage.plist
```

## Security notes

- `sessionKey` is read from Chrome's encrypted cookie store; never written to disk by the scripts
- `~/.claude/statusline.conf` is `chmod 600` (only your user can read)
- Scripts only call **read-only** endpoints on your own org. No write/delete ever.
- The 60s scrape rate is well below normal browser refresh rate. Not flagged as abuse.
- Outbound: only `claude.ai/api/organizations/<your_org>/usage`. Never sends your key elsewhere.

## Why `claude.ai` not `api.anthropic.com`?

The OAuth token Claude Code stores in macOS Keychain is **scoped to Claude Code only**. It returns 403 on `/usage` endpoints (verified). The dashboard endpoint is on `claude.ai/api/*`, served behind Cloudflare, accepts only `sessionKey` cookie auth (browser-issued).

So the scrape MUST go through:
- Browser-issued `sessionKey` (not OAuth)
- Cloudflare-passing TLS fingerprint
- Region-allowed exit IP

That's why all 3 tricks are needed.

## Credits

- [`ccusage`](https://github.com/ryoppippi/ccusage) — token/cost analysis from local transcripts
- [`tls-client`](https://github.com/bogdanfinn/tls-client) — Chrome TLS impersonation
- [`pycookiecheat`](https://github.com/n8henrie/pycookiecheat) — read browser cookies in plaintext
- [GitHub issue #32796](https://github.com/anthropics/claude-code/issues/32796) — official feature request for usage API
