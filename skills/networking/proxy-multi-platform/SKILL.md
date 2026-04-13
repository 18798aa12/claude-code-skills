---
name: proxy-multi-platform
description: Manage multi-platform proxy configurations (Quantumult X / Surge / Clash) with synchronized changes, DNS rules, strategy groups, and validation. Learned from 20+ production incidents.
author: Jope Miler, Claude
version: 1.0.0
tags: [proxy, quantumultx, surge, clash, dns, routing, multi-platform, config]
---

# Multi-Platform Proxy Configuration Management

Manage proxy configurations across three major platforms (Quantumult X, Surge, Clash/Mihomo) simultaneously. Ensures consistency, correct DNS routing, and safe modification practices. Every rule documented here was learned from real-world incidents.

## When to use

- Adding new services/domains to proxy routing rules
- Modifying DNS configurations across platforms
- Syncing changes between QX, Surge, and Clash
- Debugging DNS or routing issues
- Bulk-adding domains to proxy configurations
- Migrating or restructuring strategy groups

## The Golden Rule

**All changes MUST be applied to all three platforms simultaneously.** Never modify one platform without syncing the others.

## Platform Syntax Reference

### DNS Configuration

| Platform | Syntax | Example |
|----------|--------|---------|
| **Quantumult X** | `server=/*.domain.com/8.8.8.8` | `server=/*.google.com/8.8.8.8` |
| **Surge** | `*.domain.com = server:8.8.8.8` | `*.google.com = server:8.8.8.8` |
| **Clash** | `"*.domain.com": "8.8.8.8"` | `"*.google.com": "8.8.8.8"` |

### Filter/Routing Rules

| Platform | Syntax | Example |
|----------|--------|---------|
| **Quantumult X** | `host-suffix, domain.com, GroupName` | `host-suffix, google.com, 节点选择` |
| **Surge** | `DOMAIN-SUFFIX,domain.com,GroupName` | `DOMAIN-SUFFIX,google.com,节点选择` |
| **Clash** | `- DOMAIN-SUFFIX,domain.com,GroupName` | `- DOMAIN-SUFFIX,google.com,节点选择` |

### Strategy Group Types

| Type | QX | Surge | Clash |
|------|-----|-------|-------|
| Manual select | `static=` | `select` | `type: select` |
| Auto test | `url-latency-benchmark` | `url-test` | `type: url-test` |
| Fallback | `available` | `fallback` | `type: fallback` |
| Load balance | — | `load-balance` | `type: load-balance` |

## DNS Routing Principles

**Core rule: Domestically accessible services use domestic DNS; blocked services use overseas DNS.**

| Service Type | DNS Server | Reason |
|-------------|-----------|--------|
| Blocked (Google, YouTube, AI services) | `8.8.8.8` | Domestic DNS returns poisoned IPs |
| Domestically accessible (Apple, Microsoft, Steam) | `223.5.5.5` / `119.29.29.29` | Ensures DIRECT returns domestic CDN |
| Domestic-only (Taobao, WeChat, Alipay) | `223.5.5.5` / `119.29.29.29` | Fastest via direct connection |
| Finance (banking, trading) | `8.8.8.8` / `1.1.1.1` | Always routes through proxy |

### Clash-Specific DNS Rules

1. **NEVER use DoH domain names in nameserver-policy** — `https://dns.google/dns-query` is blocked in China, making ALL overseas DNS queries slow
2. **Use plain IP addresses** — `8.8.8.8` is much faster than DoH (no DNS-over-DNS resolution)
3. **No duplicate keys** — YAML spec requires unique map keys; duplicate `"*.domain.com"` causes parsing errors

## Section Insertion Rules

### Quantumult X

| Content | Section | Position |
|---------|---------|----------|
| DNS entries | `[dns]` | Before `[policy]` |
| Filter rules | `[filter_local]` | Before `[rewrite_local]` |
| Strategy groups | `[policy]` | After `[dns]` |

### Surge

| Content | Section | Position |
|---------|---------|----------|
| DNS entries | `[Host]` | Standard section |
| Filter rules | `[Rule]` | Before `GEOIP,CN,DIRECT` |
| Strategy groups | `[Proxy Group]` | Standard section |

### Clash

| Content | Location | Notes |
|---------|----------|-------|
| DNS entries | `dns.nameserver-policy` | No duplicate keys |
| Filter rules | `rules:` | Before `GEOIP,CN,DIRECT` |
| Strategy groups | `proxy-groups:` | YAML list items |

## Modification Workflow (MANDATORY)

### Step 1: Modify (Use Python, Never awk/sed)

```python
# ✅ CORRECT: Read → Modify in memory → Write back
with open('quantumult_x.conf', 'r') as f:
    content = f.read()

# Insert DNS before [policy]
new_dns = 'server=/*.newservice.com/8.8.8.8\n'
content = content.replace('\n[policy]', '\n' + new_dns + '[policy]')

with open('quantumult_x.conf', 'w') as f:
    f.write(content)
```

```bash
# ❌ NEVER DO THIS:
awk '!seen[$0]++' clash.yaml > temp && mv temp clash.yaml
# This deletes legitimate YAML duplicate keys! Destroyed 296 groups + 64 rule-providers

# ❌ NEVER DO THIS:
sed -i '' '/pattern/a\new line' quantumult_x.conf
# This frequently merges two lines into one
```

### Step 2: Validate

```bash
# Clash YAML syntax check
python3 -c "import yaml; yaml.safe_load(open('clash.yaml')); print('OK')"

# Check for merged lines (all platforms)
grep -c 'merged_pattern' quantumult_x.conf  # Should be 0

# DNS count alignment
echo "QX: $(grep '^server=/' quantumult_x.conf | wc -l)"
echo "Surge: $(grep '= server:' surge.conf | wc -l)"
echo "Clash: $(grep '^\s*"\*\.' clash.yaml | wc -l)"

# Duplicate strategy group options (QX)
python3 -c "
import re
with open('quantumult_x.conf') as f:
    for line in f:
        if line.startswith('static=') or line.startswith('available='):
            parts = line.strip().split(',')
            name = parts[0]
            options = [p.strip() for p in parts[1:] if p.strip()]
            dupes = [x for x in options if options.count(x) > 1]
            if dupes:
                print(f'DUPLICATE in {name}: {set(dupes)}')
"

# Duplicate DNS keys (Clash)
grep '^\s*"\*\.' clash.yaml | sed 's|.*"\*\.||; s|".*||' | sort | uniq -d
```

### Step 3: Upload to Gist

```bash
# Upload all three configs
gh gist edit $GIST_ID -f quantumult_x.conf quantumult_x.conf
gh gist edit $GIST_ID -f surge.conf surge.conf
gh gist edit $GIST_ID -f clash.yaml clash.yaml
```

### Step 4: Public Repository (Desensitized)

```bash
# Check for sensitive data before pushing
grep -c 'YOUR_REAL_IP\|YOUR_PASSWORD\|YOUR_UUID\|YOUR_GIST_ID' surge.conf clash.yaml quantumult_x.conf
# Must be 0

# Replace sensitive data
sed 's/real-server-ip/1.2.3.4/g; s/real-password/your-password/g' quantumult_x.conf > public/quantumult_x.conf
```

## Strategy Group Defaults

| Service Type | Default Region | Reason |
|-------------|---------------|--------|
| US services (AI, PayPal, Stripe, HBO, Hulu) | US | Servers located in US |
| Global services (YouTube, Netflix, Social) | Hong Kong | Closest, fastest |
| UK platforms (BBC, ITV) | UK | Geo-restricted |
| Japan platforms (Niconico, AbemaTV) | Japan | Geo-restricted |
| Korea platforms (Wavve, Tving) | Korea | Geo-restricted |
| Adult content | Japan | Not blocked |
| Domestically accessible (Apple, Steam, Xbox) | DIRECT | Direct is fastest |
| Finance/Banking | Dedicated node | IP must be fixed |

## Auto-Fix: Common Issues

### DNS Entry in Wrong Section

```bash
# Symptom: DNS entries appear in [filter_local] instead of [dns]
# Cause: Python script inserted at wrong position

# Detection
grep '^server=/' quantumult_x.conf | head -5
# Check: are these lines between [dns] and [policy]?

# Fix: Move misplaced entries
python3 << 'PYEOF'
with open('quantumult_x.conf', 'r') as f:
    content = f.read()

# Extract DNS lines from wrong sections
import re
# Find DNS lines outside [dns] section and move them
# ... (implementation depends on specific file structure)
PYEOF
```

### Three Platforms Out of Sync

```bash
# Detection: Compare key metrics
echo "=== DNS Count ==="
echo "QX:    $(grep -c '^server=/' quantumult_x.conf)"
echo "Surge: $(grep -c '= server:' surge.conf)"
echo "Clash: $(grep -c '^\s*"\*\.' clash.yaml)"

echo "=== Filter Rule Count ==="
echo "QX:    $(grep -c '^host-suffix' quantumult_x.conf)"
echo "Surge: $(grep -c '^DOMAIN-SUFFIX' surge.conf)"
echo "Clash: $(grep -c '^ *- DOMAIN-SUFFIX' clash.yaml)"

echo "=== Strategy Group Count ==="
echo "QX:    $(grep -c '^static=\|^available=\|^url-latency-benchmark=' quantumult_x.conf)"
echo "Surge: $(grep -c '= select\|= url-test\|= fallback' surge.conf)"
echo "Clash: $(grep -c 'type: select\|type: url-test\|type: fallback' clash.yaml)"

# Numbers should be approximately equal (±5 for platform-specific entries)
```

### Clash Case Sensitivity

```bash
# Symptom: Clash rules not matching
# Cause: Clash requires uppercase action keywords

# ❌ WRONG
# - DOMAIN-SUFFIX,google.com,direct     # lowercase 'direct'
# - DOMAIN-SUFFIX,ads.com,reject        # lowercase 'reject'

# ✅ CORRECT
# - DOMAIN-SUFFIX,google.com,DIRECT     # uppercase
# - DOMAIN-SUFFIX,ads.com,REJECT        # uppercase

# Auto-fix
sed -i '' 's/,direct$/,DIRECT/; s/,reject$/,REJECT/' clash.yaml
```

### QX Strategy Group Errors

```bash
# Issue 1: `available` can only reference nodes, not groups
# ❌ available=Fallback, 节点选择, 香港, 美国
# ✅ available=Fallback, server-tag-regex=.*, img-url=...

# Issue 2: `url-latency-benchmark` needs explicit members or resource-tag-regex
# ❌ url-latency-benchmark=Hong Kong   (empty group!)
# ✅ url-latency-benchmark=Hong Kong, server-tag-regex=(?=.*(港|HK|Hong))

# Issue 3: Duplicate options in static= line
# Detection:
python3 -c "
with open('quantumult_x.conf') as f:
    for i, line in enumerate(f, 1):
        if 'static=' in line:
            parts = [p.strip() for p in line.split(',')]
            seen = set()
            for p in parts[1:]:
                if p in seen and p:
                    print(f'Line {i}: duplicate \"{p}\"')
                seen.add(p)
"
```

### Apple/Microsoft Store Not Working

```bash
# Symptom: App Store or Microsoft Store can't connect
# Cause: Apple/Microsoft DNS using overseas server (8.8.8.8)
#         → DNS returns overseas CDN IP
#         → DIRECT rule tries to connect to overseas CDN from China
#         → Timeout

# Fix: Use domestic DNS for domestically-accessible services
# QX:    server=/*.apple.com/223.5.5.5
# Surge: *.apple.com = server:223.5.5.5
# Clash: "*.apple.com": "223.5.5.5"

# Also check: DIRECT rules must come BEFORE RULE-SET rules
# Otherwise the RULE-SET matches first and overrides DIRECT
```

## Bulk Domain Addition Workflow

When adding many domains at once (e.g., supporting a new service category):

1. **Research phase**: Use 3-4 parallel agents to search domains by category
2. **Classification**: Determine each domain's type (domestic/overseas/amphibious)
3. **DNS assignment**: Domestic DNS for direct, overseas DNS for proxied
4. **Filter rules**: Map to correct strategy group
5. **Validation**: Run the full validation suite
6. **Orphan audit**: Check for DNS entries without matching filter rules
7. **Real device test**: Test on actual devices after bulk changes

```bash
# Orphan DNS audit (DNS entries without matching filter rules)
# QX example:
comm -23 \
  <(grep '^server=/' quantumult_x.conf | sed 's|server=/\*\.||; s|/.*||' | sort -u) \
  <(grep '^host-suffix' quantumult_x.conf | sed 's|host-suffix, ||; s|,.*||' | sort -u)
# Output = DNS entries with no filter rule (orphans to fix)
```

## Platform-Specific Notes

### Quantumult X
- JavaScript engine: ES5 only (`var`, `function(){}`, no arrow functions, no `let`/`const`)
- `$done({title, message})` for event-interaction scripts (NOT `$notify`)
- `$notify(title, subtitle, body)` for cron scripts only
- Script output: max 12 lines (iPhone screen limit)

### Surge
- Supports JavaScript with modern syntax
- Module system for modular configs
- HTTPS decryption via MitM certificate

### Clash/Mihomo
- YAML format — case-sensitive (`DIRECT` not `direct`)
- `nameserver-policy` — no DoH domains, use plain IPs only
- Local nodes need explicit `proxies:` declaration (subscription `use:` + `filter:` won't include them)
- `yaml.dump()` may reorder keys — use string operations for precise control
