---
name: cf-auto-checkin
description: Auto-checkin CF Workers with Telegram notifications. Two login patterns (API token and Cookie-based), cron triggers, multi-target TG push, and production-tested cookie parsing strategies.
author: Jope Miler, Claude
version: 1.0.0
tags: [cloudflare, workers, cron, checkin, telegram, automation, serverless]
---

# Cloudflare Workers Auto-Checkin

Deploy automated daily checkin Workers on Cloudflare with Telegram notifications. Supports two battle-tested login patterns for different site architectures, with cron triggers and multi-target push.

## When to use

- Automating daily checkin/sign-in on web services
- Need Telegram notifications for checkin results
- Want zero-maintenance auto-login that never expires (API pattern)
- Site uses PHP sessions and needs robust cookie handling (Cookie pattern)
- Running scheduled tasks on Cloudflare Workers with cron triggers

## Login Patterns

### Pattern A: API Auto-Login (Recommended)

Best for sites with a REST API that returns an auth token on login. The Worker logs in fresh every time, so tokens never expire.

**Flow:** POST login → get token → POST checkin → TG notify

### Pattern B: Cookie-Based Login

Best for traditional PHP sites that use session cookies (PHPSESSID). Includes 5 parallel cookie parsing strategies for maximum compatibility with different server behaviors.

**Flow:** GET login page (cookie) → POST login (merge cookies) → POST checkin → TG notify

## Auto-Setup: Pattern A (API Login)

### Step 1: Create Project

```bash
mkdir my-checkin && cd my-checkin
npm init -y
```

### Step 2: Create Worker

Create `src/worker.js`:

```javascript
/**
 * Auto-Checkin CF Worker — API Login Pattern
 * Logs in with email/password to get a fresh token, then checks in.
 * Token is never stored — obtained fresh each run, so it never expires.
 */

export default {
    async scheduled(event, env, ctx) {
        ctx.waitUntil(runCheckin(env));
    },

    async fetch(request, env) {
        const result = await runCheckin(env);
        return new Response(JSON.stringify(result, null, 2), {
            headers: { "Content-Type": "application/json" },
        });
    },
};

async function runCheckin(env) {
    const results = [];

    // ── Add your sites here ──
    const sites = [
        {
            name: "MY_SITE_NAME",
            baseUrl: "https://YOUR_SITE_DOMAIN",
            loginPath: "/api/v1/passport/auth/login",
            checkinPath: "/api/v1/user/checkin",
            email: env.SITE_EMAIL,
            password: env.SITE_PASSWORD,
        },
        // Add more sites as needed:
        // {
        //     name: "Another Site",
        //     baseUrl: "https://another-site.com",
        //     loginPath: "/api/login",
        //     checkinPath: "/api/checkin",
        //     email: env.SITE2_EMAIL,
        //     password: env.SITE2_PASSWORD,
        // },
    ];

    for (const site of sites) {
        if (!site.email || !site.password) {
            results.push({ name: site.name, ok: false, msg: "Email/password not configured" });
            continue;
        }
        const r = await loginAndCheckin(site);
        results.push(r);
    }

    await sendTelegram(env, results);
    return results;
}

async function loginAndCheckin(site) {
    const ua = "Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/136.0.0.0 Safari/537.36";

    try {
        // Step 1: Login to get fresh token
        const loginResp = await fetch(`${site.baseUrl}${site.loginPath}`, {
            method: "POST",
            headers: { "Content-Type": "application/json", "User-Agent": ua },
            body: JSON.stringify({ email: site.email, password: site.password }),
        });

        const loginData = await loginResp.json();

        // Adjust this based on your site's API response format
        if (!loginData.data || !loginData.data.auth_data) {
            return { name: site.name, ok: false, msg: `Login failed: ${loginData.message || "unknown"}` };
        }

        const token = loginData.data.auth_data;

        // Step 2: Checkin with fresh token
        const checkinResp = await fetch(`${site.baseUrl}${site.checkinPath}`, {
            method: "POST",
            headers: {
                "Content-Type": "application/json",
                Authorization: token,
                "User-Agent": ua,
                Origin: site.baseUrl,
                Referer: site.baseUrl + "/",
            },
        });

        const checkinData = await checkinResp.json().catch(() => ({ message: "Parse error" }));

        if (checkinResp.status === 200) {
            return { name: site.name, ok: true, msg: checkinData.data || checkinData.message || "Checkin success" };
        } else if (checkinResp.status === 400) {
            return { name: site.name, ok: true, msg: checkinData.message || "Already checked in today" };
        } else {
            return { name: site.name, ok: false, msg: `HTTP ${checkinResp.status}: ${checkinData.message || "error"}` };
        }
    } catch (e) {
        return { name: site.name, ok: false, msg: `Request error: ${e.message}` };
    }
}

async function sendTelegram(env, results) {
    const token = env.TG_BOT_TOKEN;
    if (!token) return;

    // Configure your notification targets
    const chatIds = [
        env.TG_CHAT_ID,       // Primary user
        // env.TG_CHAT_ID_2,  // Secondary user (optional)
        // env.TG_CHANNEL_ID, // Channel (optional)
    ].filter(Boolean);

    if (chatIds.length === 0) return;

    const now = new Date().toLocaleString("zh-CN", { timeZone: "Asia/Shanghai" });
    const lines = results.map((r) => {
        const icon = r.ok ? "\u2705" : "\u274c";
        return `${icon} <b>${r.name}</b>\n   ${r.msg}`;
    });

    const text = `\ud83d\udd50 <b>Auto-Checkin Report</b>\n\ud83d\udcc5 ${now}\n\n${lines.join("\n\n")}`;

    for (const chatId of chatIds) {
        await fetch(`https://api.telegram.org/bot${token}/sendMessage`, {
            method: "POST",
            headers: { "Content-Type": "application/json" },
            body: JSON.stringify({ chat_id: chatId, text, parse_mode: "HTML" }),
        });
    }
}
```

### Step 3: Configure wrangler.toml

```toml
name = "my-checkin"
main = "src/worker.js"
compatibility_date = "2024-12-01"
account_id = "YOUR_CF_ACCOUNT_ID"

# Cron schedule (UTC). Examples:
# "0 21 * * *"  = Beijing 5:00 AM daily
# "0 0 * * *"   = Beijing 8:00 AM daily
# "30 16 * * *" = Beijing 0:30 AM daily
[triggers]
crons = ["0 21 * * *"]

# Optional: plain-text vars (non-sensitive)
# [vars]
# TG_CHAT_ID = "YOUR_CHAT_ID"
```

### Step 4: Set Secrets and Deploy

```bash
# Set secrets (never put these in wrangler.toml)
echo "YOUR_EMAIL" | npx wrangler secret put SITE_EMAIL
echo "YOUR_PASSWORD" | npx wrangler secret put SITE_PASSWORD
echo "YOUR_BOT_TOKEN" | npx wrangler secret put TG_BOT_TOKEN
echo "YOUR_CHAT_ID" | npx wrangler secret put TG_CHAT_ID

# Deploy
npx wrangler deploy
```

## Auto-Setup: Pattern B (Cookie Login)

### Step 1: Create Project

```bash
mkdir my-cookie-checkin && cd my-cookie-checkin
npm init -y
```

### Step 2: Create Worker

Create `src/worker.js`:

```javascript
/**
 * Auto-Checkin CF Worker — Cookie Login Pattern
 * For PHP sites using session cookies (PHPSESSID).
 * Runs 5 cookie parsing strategies in parallel for maximum compatibility.
 */

let domain = "";
let user = "";
let pass = "";
let BotToken = "";
let ChatID = "";

export default {
    async fetch(request, env, ctx) {
        await initVars(env);
        const url = new URL(request.url);
        if (url.pathname === "/checkin") {
            await checkin();
        }
        return new Response("OK", { status: 200 });
    },

    async scheduled(controller, env, ctx) {
        try {
            await initVars(env);
            await checkin();
        } catch (error) {
            console.error("Cron failed:", error);
        }
    },
};

async function initVars(env) {
    domain = env.SITE_DOMAIN || domain;
    user = env.SITE_EMAIL || user;
    pass = env.SITE_PASSWORD || pass;
    if (domain && !domain.includes("//")) domain = `https://${domain}`;
    BotToken = env.TG_BOT_TOKEN || BotToken;
    ChatID = env.TG_CHAT_ID || ChatID;
}

async function sendMessage(msg = "") {
    const now = new Date(Date.now() + 8 * 3600000).toISOString().slice(0, 19).replace("T", " ");
    if (BotToken && ChatID) {
        const url = `https://api.telegram.org/bot${BotToken}/sendMessage`;
        await fetch(url, {
            method: "POST",
            headers: { "Content-Type": "application/json" },
            body: JSON.stringify({
                chat_id: ChatID,
                parse_mode: "HTML",
                text: `\ud83d\udd50 ${now}\n\n${msg}`,
            }),
        });
    }
}

// ── 5 Cookie Parsing Strategies ──
// Different servers serialize Set-Cookie headers differently.
// Running all 5 in parallel maximizes compatibility.

const COOKIE_ATTRS = new Set(["expires", "max-age", "path", "domain", "secure", "httponly", "samesite"]);

const COOKIE_STRATEGIES = [
    // Strategy 1: getSetCookie() — CF Workers standard API
    function strategyGetSetCookie(response) {
        if (typeof response.headers.getSetCookie !== "function") return "";
        const cookies = [];
        for (const sc of response.headers.getSetCookie()) {
            const semi = sc.indexOf(";");
            const pair = (semi > 0 ? sc.substring(0, semi) : sc).trim();
            if (pair.includes("=")) cookies.push(pair);
        }
        return cookies.join("; ");
    },

    // Strategy 2: headers.entries() iteration
    function strategyEntries(response) {
        const cookies = [];
        try {
            for (const [name, value] of response.headers.entries()) {
                if (name.toLowerCase() !== "set-cookie") continue;
                const matches = value.matchAll(/(?:^|[,;]\s*)([a-zA-Z_][a-zA-Z0-9_-]*=[^;,]*)/g);
                for (const m of matches) {
                    const pair = m[1].trim();
                    const eq = pair.indexOf("=");
                    if (eq > 0 && !COOKIE_ATTRS.has(pair.substring(0, eq).toLowerCase())) cookies.push(pair);
                }
            }
        } catch (e) {}
        return cookies.join("; ");
    },

    // Strategy 3: raw header + matchAll regex
    function strategyMatchAll(response) {
        const raw = response.headers.get("set-cookie") || "";
        if (!raw) return "";
        const cookies = [];
        const matches = raw.matchAll(/(?:^|[,;]\s*)([a-zA-Z_][a-zA-Z0-9_-]*=[^;,]*)/g);
        for (const m of matches) {
            const pair = m[1].trim();
            const eq = pair.indexOf("=");
            if (eq > 0 && !COOKIE_ATTRS.has(pair.substring(0, eq).toLowerCase())) cookies.push(pair);
        }
        return cookies.join("; ");
    },

    // Strategy 4: split by [;,] + attribute blacklist
    function strategySplitFilter(response) {
        const raw = response.headers.get("set-cookie") || "";
        if (!raw) return "";
        const cookies = [];
        for (const part of raw.split(/[;,]\s*/)) {
            const pair = part.trim();
            const eq = pair.indexOf("=");
            if (eq <= 0) continue;
            if (!COOKIE_ATTRS.has(pair.substring(0, eq).trim().toLowerCase())) cookies.push(pair);
        }
        return cookies.join("; ");
    },

    // Strategy 5: smart comma split (handles Expires=Wed, DD-Mon-YYYY commas)
    function strategySmartCommaSplit(response) {
        const raw = response.headers.get("set-cookie") || "";
        if (!raw) return "";
        const segments = raw.split(/,(?=\s*[a-zA-Z_][a-zA-Z0-9_-]*=)/);
        const cookies = [];
        for (const seg of segments) {
            const pair = seg.split(";")[0].trim();
            const eq = pair.indexOf("=");
            if (eq <= 0) continue;
            if (!COOKIE_ATTRS.has(pair.substring(0, eq).trim().toLowerCase())) cookies.push(pair);
        }
        return cookies.join("; ");
    },
];

function mergeCookies(oldStr, newStr) {
    const map = new Map();
    for (const c of (oldStr || "").split("; ").filter(Boolean)) {
        const eq = c.indexOf("=");
        if (eq > 0) map.set(c.substring(0, eq).trim(), c);
    }
    for (const c of (newStr || "").split("; ").filter(Boolean)) {
        const eq = c.indexOf("=");
        if (eq > 0) map.set(c.substring(0, eq).trim(), c);
    }
    return Array.from(map.values()).join("; ");
}

async function checkin() {
    if (!domain || !user || !pass) return;

    const tasks = COOKIE_STRATEGIES.map((strategy, i) => attemptCheckin(i + 1, strategy));
    const results = await Promise.allSettled(tasks);

    for (const r of results) {
        if (r.status === "fulfilled" && r.value && r.value.success) {
            await sendMessage(r.value.message);
            return;
        }
    }

    const errors = results.map((r) =>
        r.status === "fulfilled" ? r.value?.message : r.reason?.message || String(r.reason)
    );
    await sendMessage(`All 5 attempts failed:\n${errors.join("\n")}`);
}

async function attemptCheckin(attemptNo, extractCookies) {
    const ua = "Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/136.0.0.0 Safari/537.36";

    try {
        // Step 1: GET login page for initial session cookie
        const initResp = await fetch(`${domain}/auth/login`, {
            method: "GET",
            headers: { "User-Agent": ua },
            redirect: "manual",
        });
        let allCookies = extractCookies(initResp);

        // Step 2: POST login
        const loginResp = await fetch(`${domain}/auth/login`, {
            method: "POST",
            headers: {
                "Content-Type": "application/json",
                "User-Agent": ua,
                Cookie: allCookies,
                Origin: domain,
                Referer: `${domain}/auth/login`,
            },
            body: JSON.stringify({ email: user, passwd: pass, remember_me: "on", code: "" }),
            redirect: "manual",
        });

        allCookies = mergeCookies(allCookies, extractCookies(loginResp));

        const loginText = await loginResp.text();
        try {
            const loginJson = JSON.parse(loginText);
            if (loginJson.ret !== 1) throw new Error(`Login failed: ${loginJson.msg || "unknown"}`);
        } catch (e) {
            if (e.message.startsWith("Login failed")) throw e;
            if (loginResp.status >= 400) throw new Error(`Login failed: HTTP ${loginResp.status}`);
        }

        if (!allCookies || !allCookies.toLowerCase().includes("phpsessid")) {
            throw new Error("Missing PHPSESSID after login");
        }

        // Step 3: POST checkin
        const checkinResp = await fetch(`${domain}/user/checkin`, {
            method: "POST",
            headers: {
                Cookie: allCookies,
                "User-Agent": ua,
                "Content-Type": "application/json",
                Origin: domain,
                Referer: `${domain}/user`,
                "X-Requested-With": "XMLHttpRequest",
            },
        });

        const respText = await checkinResp.text();
        try {
            const result = JSON.parse(respText);
            return { success: true, message: `Checkin result: ${result.msg || "done"}` };
        } catch (e) {
            return { success: false, message: `[Attempt ${attemptNo}] Parse error: ${respText.substring(0, 100)}` };
        }
    } catch (error) {
        return { success: false, message: `[Attempt ${attemptNo}] ${error.message}` };
    }
}
```

### Step 3: Configure wrangler.toml

```toml
name = "my-cookie-checkin"
main = "src/worker.js"
compatibility_date = "2024-12-01"
account_id = "YOUR_CF_ACCOUNT_ID"

[triggers]
crons = ["0 21 * * *"]
```

### Step 4: Set Secrets and Deploy

```bash
echo "example.com" | npx wrangler secret put SITE_DOMAIN
echo "user@example.com" | npx wrangler secret put SITE_EMAIL
echo "your_password" | npx wrangler secret put SITE_PASSWORD
echo "123456789:AABBccDDeeFFgg" | npx wrangler secret put TG_BOT_TOKEN
echo "123456789" | npx wrangler secret put TG_CHAT_ID

npx wrangler deploy
```

## Telegram Bot Setup

### Step 1: Create Bot

1. Message [@BotFather](https://t.me/BotFather) on Telegram
2. Send `/newbot`, follow prompts
3. Copy the bot token (format: `123456789:AABBccDDeeFFgg...`)

### Step 2: Get Chat ID

```bash
# Send any message to your bot first, then:
curl -s "https://api.telegram.org/bot<YOUR_BOT_TOKEN>/getUpdates" | python3 -m json.tool

# Look for "chat": {"id": 123456789} in the response
```

### Step 3: Multi-Target Push (Optional)

To send to multiple users or channels:

```javascript
// In sendTelegram(), add more targets:
const chatIds = [
    env.TG_CHAT_ID,       // User 1
    env.TG_CHAT_ID_2,     // User 2
    env.TG_CHANNEL_ID,    // Channel (use negative ID, e.g., -100xxx)
].filter(Boolean);
```

Set each as a secret or `[vars]` in wrangler.toml:

```bash
echo "USER1_CHAT_ID" | npx wrangler secret put TG_CHAT_ID
echo "USER2_CHAT_ID" | npx wrangler secret put TG_CHAT_ID_2
echo "-100CHANNEL_ID" | npx wrangler secret put TG_CHANNEL_ID
```

## Cron Schedule Reference

Cloudflare cron triggers use **UTC** time.

| Beijing Time | UTC Cron | Expression |
|-------------|----------|------------|
| 00:00 (midnight) | `0 16 * * *` | Previous day 16:00 UTC |
| 01:00 | `0 17 * * *` | Previous day 17:00 UTC |
| 05:00 | `0 21 * * *` | Previous day 21:00 UTC |
| 08:00 | `0 0 * * *` | 00:00 UTC |
| 12:00 (noon) | `0 4 * * *` | 04:00 UTC |
| 18:00 | `0 10 * * *` | 10:00 UTC |

**Tip:** Beijing = UTC + 8. To convert: subtract 8 from Beijing hour. If result < 0, add 24 (it's previous day UTC).

## Custom Domain (Optional)

`workers.dev` may return error 1101 in some regions. Bind a custom domain:

```toml
# wrangler.toml
routes = [{ pattern = "checkin.example.com/*", zone_name = "example.com" }]
```

```bash
# Add DNS record (dummy AAAA, CF proxied)
curl -X POST "https://api.cloudflare.com/client/v4/zones/$ZONE_ID/dns_records" \
  -H "Authorization: Bearer $API_TOKEN" \
  -H "Content-Type: application/json" \
  -d '{"type":"AAAA","name":"checkin","content":"100::","proxied":true}'

# Deploy
npx wrangler deploy

# Test
curl https://checkin.example.com/
```

## Manual Trigger

```bash
# Via custom domain (if configured)
curl https://checkin.example.com/

# Via wrangler dev (local test with .dev.vars for secrets)
npx wrangler dev --test-scheduled
# Then visit: http://localhost:8787/__scheduled
```

## Auto-Fix: Cron Not Firing

```bash
# Symptom: No TG notification at scheduled time
# Cause 1: Secrets not set on production Worker

# Check deployed secrets
npx wrangler secret list
# Should show all required secrets (SITE_EMAIL, SITE_PASSWORD, TG_BOT_TOKEN, TG_CHAT_ID, etc.)

# Cause 2: wrangler.toml changed but not deployed
npx wrangler deploy

# Cause 3: Cron schedule not active
# Verify via API:
curl -s "https://api.cloudflare.com/client/v4/accounts/$ACCOUNT_ID/workers/scripts/$WORKER_NAME/schedules" \
  -H "Authorization: Bearer $API_TOKEN" | python3 -m json.tool
```

## Auto-Fix: Token / Session Expired

```bash
# Symptom: "Token expired" or "401 Unauthorized"
# Cause: Using a stored auth token that has expired

# Fix: Switch to Pattern A (API Login) — logs in fresh every run, tokens never expire
# See the Pattern A setup above. Store email + password as secrets instead of a token.
```

## Auto-Fix: Cookie Login Fails

```bash
# Symptom: All 5 cookie strategies fail, "Missing PHPSESSID"
# Cause: Site changed login flow, added CAPTCHA, or changed cookie behavior

# Debug: Check login response manually
curl -v "https://YOUR_SITE/auth/login" 2>&1 | grep -i set-cookie

# Common fixes:
# 1. Site added CAPTCHA → Cookie pattern won't work, switch to Pattern A if API exists
# 2. Site changed login endpoint → Update loginPath in the sites array
# 3. Site changed cookie name → Update the PHPSESSID check in the code
```

## Auto-Fix: TG Notification Not Received

```bash
# Symptom: Checkin works but no Telegram message
# Cause 1: Bot token invalid
curl -s "https://api.telegram.org/bot<TOKEN>/getMe" | python3 -m json.tool

# Cause 2: Chat ID wrong — must message the bot first
curl -s "https://api.telegram.org/bot<TOKEN>/getUpdates" | python3 -m json.tool

# Cause 3: Channel ID needs -100 prefix
# Group/channel IDs are negative: -1001234567890

# Cause 4: Bot not added to channel/group
# Add the bot as admin to the channel, then try sending
```

## Multi-Site Configuration

Both patterns support multiple sites. Add entries to the `sites` array:

```javascript
const sites = [
    {
        name: "Site A",
        baseUrl: "https://site-a.com",
        loginPath: "/api/v1/passport/auth/login",
        checkinPath: "/api/v1/user/checkin",
        email: env.SITE_A_EMAIL,
        password: env.SITE_A_PASSWORD,
    },
    {
        name: "Site B",
        baseUrl: "https://site-b.com",
        loginPath: "/api/login",
        checkinPath: "/api/checkin",
        email: env.SITE_B_EMAIL,
        password: env.SITE_B_PASSWORD,
    },
];
```

Set secrets for each:

```bash
echo "a@example.com" | npx wrangler secret put SITE_A_EMAIL
echo "pass_a" | npx wrangler secret put SITE_A_PASSWORD
echo "b@example.com" | npx wrangler secret put SITE_B_EMAIL
echo "pass_b" | npx wrangler secret put SITE_B_PASSWORD
```

## Security Notes

- **Never** put credentials in `wrangler.toml` or source code — use `wrangler secret put`
- Use `.dev.vars` for local testing (this file should be in `.gitignore`)
- Bot tokens and passwords are stored as encrypted secrets on Cloudflare's edge
- The Worker source code contains no user data — safe to open-source

## Useful Commands

```bash
npx wrangler secret list                    # List all secrets
npx wrangler secret put SECRET_NAME         # Add/update a secret
npx wrangler secret delete SECRET_NAME      # Remove a secret
npx wrangler deploy                         # Deploy Worker + cron
npx wrangler tail                           # Stream live logs
npx wrangler deployments list               # View deployment history
```
