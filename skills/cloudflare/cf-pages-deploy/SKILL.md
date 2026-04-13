---
name: cf-pages-deploy
description: Deploy services on Cloudflare Pages with wrangler. Covers Pages vs Workers decision, proxy deployment, common pitfalls, and auto-fix for 1101 errors and build failures.
author: Jope Miler, Claude
version: 1.0.0
tags: [cloudflare, pages, workers, wrangler, deploy, serverless, proxy]
---

# Cloudflare Pages Deployment

Deploy web services, APIs, and proxy applications on Cloudflare Pages. Includes critical knowledge on Pages vs Workers selection, deployment pitfalls, and automated troubleshooting.

## When to use

- Deploying a web application to Cloudflare's edge network
- Setting up proxy services (VLESS/Trojan) on Cloudflare
- Getting error 1101 on Workers and need to migrate to Pages
- Need to understand Pages vs Workers trade-offs
- Troubleshooting wrangler deployment failures

## Critical Decision: Pages vs Workers

### When to use Pages (RECOMMENDED for most cases)

| Use Case | Why Pages |
|----------|-----------|
| Static sites + API | Built-in static hosting + Functions |
| Proxy services (VLESS/Trojan) | Workers actively detects and blocks proxy code with error 1101 |
| Any HTTP service | No detection/blocking issues |
| Custom domains | First-class support via DNS CNAME |

### When to use Workers

| Use Case | Why Workers |
|----------|------------|
| Cron triggers | Pages doesn't support `[triggers]` |
| Durable Objects | Only available on Workers |
| WebSocket server (non-proxy) | Better WebSocket support |
| Email routing | Workers-only feature |

### The 1101 Problem

**Cloudflare actively detects and blocks proxy code on Workers.** Even if it works initially, it gets flagged within minutes and returns error 1101. Pages does NOT have this detection.

```
# Workers: ❌ Blocked with 1101
https://my-worker.workers.dev → Error 1101

# Workers with custom domain: ❌ Still blocked
https://proxy.example.com (routed to Worker) → Error 1101

# Pages: ✅ Works fine
https://proxy.example.com (Pages project) → 200 OK
```

**Note:** `workers.dev` subdomain itself often returns 1101 even for non-proxy Workers in some regions. Always bind a custom domain.

## Auto-Setup Flow

### Step 1: Project Structure

```bash
# Create project directory
mkdir my-cf-project && cd my-cf-project

# Create wrangler.toml for Pages
cat > wrangler.toml << 'EOF'
name = "my-project"
pages_build_output_dir = "dist"
compatibility_date = "2024-12-01"
# Add if using Node.js APIs (crypto, buffer, etc.):
# compatibility_flags = ["nodejs_compat"]
EOF

# Create the output directory
mkdir -p dist
```

### Step 2: Place Your Code

```bash
# For Pages, the entry point is _worker.js in the output directory
# Place your application code here:
cp your-app.js dist/_worker.js
```

### Step 3: Deploy

```bash
# Login to Cloudflare (first time only)
npx wrangler login

# Deploy to Pages
npx wrangler pages deploy dist --project-name my-project

# Or if wrangler.toml is configured:
npx wrangler pages deploy
```

### Step 4: Bind Custom Domain

```bash
# Via Cloudflare Dashboard:
# Pages project → Custom domains → Add domain → example.com

# Or via API:
curl -X POST "https://api.cloudflare.com/client/v4/accounts/$ACCOUNT_ID/pages/projects/$PROJECT_NAME/domains" \
  -H "Authorization: Bearer $API_TOKEN" \
  -H "Content-Type: application/json" \
  -d '{"name":"app.example.com"}'
```

## Proxy Deployment (VLESS/Trojan)

### VLESS on Pages

```toml
# wrangler.toml
name = "vless-proxy"
pages_build_output_dir = "dist"
compatibility_date = "2024-12-01"
```

**Critical rules:**
1. Use the **cleartext (terser-minified)** version, NOT obfuscated
2. Obfuscated code causes wrangler esbuild `const reassignment` errors
3. If you must use obfuscated code, add `globalThis.window = globalThis` shim at the top of `_worker.js`
4. Only TLS ports work (443, 2053, 2083, 2087, 2096, 8443) — HTTP ports (80, 8080, etc.) do NOT work on Pages

### Trojan on Pages

```toml
# wrangler.toml
name = "trojan-proxy"
pages_build_output_dir = "dist"
compatibility_date = "2024-12-01"
compatibility_flags = ["nodejs_compat"]  # REQUIRED for require("crypto")
```

### Password Rules

- Do NOT use `=` or special URL characters in passwords
- These cause empty responses or URL parsing failures
- Safe characters: `A-Za-z0-9!@#$%^&*()-_+`

## Workers with Custom Domain (Non-Proxy)

If you must use Workers (for cron, Durable Objects, etc.):

```bash
# Step 1: Create a dummy DNS A record
# The IP doesn't matter — CF proxies the traffic
# Use the reserved documentation IP:
curl -X POST "https://api.cloudflare.com/client/v4/zones/$ZONE_ID/dns_records" \
  -H "Authorization: Bearer $API_TOKEN" \
  -H "Content-Type: application/json" \
  -d '{
    "type": "A",
    "name": "api",
    "content": "192.0.2.1",
    "proxied": true
  }'

# Step 2: Add Worker route (must include /* wildcard)
# In wrangler.toml:
# routes = [{ pattern = "api.example.com/*", zone_name = "example.com" }]
```

**Important:** Worker routes MUST include the `/*` wildcard suffix, or requests to subpaths won't be routed.

## Auto-Fix: Common Deployment Errors

### Error: 1101 (Worker Blocked)

```bash
# Symptom: Worker returns error 1101
# Cause: Cloudflare detected proxy code on Workers

# Fix: Migrate to Pages
# 1. Create dist/ directory with _worker.js
mkdir -p dist
cp worker.js dist/_worker.js

# 2. Create wrangler.toml for Pages
cat > wrangler.toml << 'EOF'
name = "my-project"
pages_build_output_dir = "dist"
compatibility_date = "2024-12-01"
EOF

# 3. Deploy as Pages
npx wrangler pages deploy dist --project-name my-project

# 4. Delete the old Worker
npx wrangler delete my-worker
```

### Error: "const reassignment" During Build

```bash
# Symptom: wrangler build fails with "Assignment to constant variable"
# Cause: Obfuscated code reassigns const variables, incompatible with esbuild

# Fix Option A: Use cleartext (terser-minified) version instead
# Fix Option B: Add shim at top of _worker.js:
echo 'globalThis.window = globalThis;' | cat - dist/_worker.js > temp && mv temp dist/_worker.js
```

### Error: "require is not defined"

```bash
# Symptom: Runtime error "require is not defined" (usually for crypto)
# Cause: Missing nodejs_compat flag

# Fix: Add to wrangler.toml:
# compatibility_flags = ["nodejs_compat"]
```

### Error: Empty Response / 520

```bash
# Symptom: Page loads but returns empty body or 520 error
# Cause: Password contains = or special URL characters

# Fix: Change password to alphanumeric + safe special chars only
# Bad:  "myPass=123&test"
# Good: "MySecurePass2024!"
```

### Error: Custom Domain Not Working

```bash
# Symptom: Custom domain returns 522 or DNS error
# Cause: DNS record not properly configured

# Fix for Pages:
# 1. Go to Pages project → Custom domains
# 2. Add your domain — CF automatically creates CNAME record

# Fix for Workers:
# 1. Create A record pointing to 192.0.2.1 (proxied)
# 2. Add route: "app.example.com/*" in wrangler.toml
# Note: Do NOT CNAME to workers.dev — it doesn't work
```

### Error: Pages Project Limit Reached

```bash
# Symptom: "You have reached the maximum number of Pages projects"
# Free plan limit: ~100 projects

# Fix: Delete unused projects
npx wrangler pages project list
npx wrangler pages project delete old-project-name
```

## Deployment Checklist

Before deploying:
- [ ] `_worker.js` is in the `pages_build_output_dir` directory
- [ ] `wrangler.toml` has correct `pages_build_output_dir`
- [ ] If using Node.js APIs: `compatibility_flags = ["nodejs_compat"]`
- [ ] If proxy: using cleartext code (not obfuscated)
- [ ] Password doesn't contain `=` or URL-special characters
- [ ] Custom domain configured (don't rely on `*.pages.dev` or `workers.dev`)

After deploying:
- [ ] Custom domain returns 200
- [ ] Service functions correctly (test the main flow)
- [ ] No 1101 or 520 errors
- [ ] SSL certificate is active (may take a few minutes)

## Useful Commands

```bash
# List all Pages projects
npx wrangler pages project list

# View deployment history
npx wrangler pages deployment list --project-name my-project

# Tail logs (live)
npx wrangler pages deployment tail --project-name my-project

# Delete a project
npx wrangler pages project delete my-project

# Check Cloudflare API token permissions
curl -s "https://api.cloudflare.com/client/v4/user/tokens/verify" \
  -H "Authorization: Bearer $API_TOKEN" | jq .
```

## Platform Limitations

| Feature | Pages | Workers |
|---------|-------|---------|
| Static hosting | ✅ Built-in | ❌ Need R2/KV |
| Custom domains | ✅ Easy | ⚠️ Need DNS + route |
| Proxy code | ✅ No detection | ❌ Blocked (1101) |
| Cron triggers | ❌ | ✅ |
| Durable Objects | ❌ | ✅ |
| WebSocket server | ⚠️ Limited | ✅ Full |
| TLS-only ports | ✅ 443/2053/2083/2087/2096/8443 | ✅ Same |
| HTTP ports | ❌ Not for Pages | ✅ Via route |
| Build pipeline | ✅ Git integration | ⚠️ Manual |
| Preview deployments | ✅ Per-branch | ❌ |
