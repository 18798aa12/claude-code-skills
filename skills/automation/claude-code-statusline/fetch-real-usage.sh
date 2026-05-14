#!/bin/bash
# Scrape claude.ai/api/organizations/<org>/usage → real Anthropic plan usage data
# Bypasses 3 protections: region-block (via local proxy), Cloudflare TLS fingerprint
# (tls-client), session expiry (read live from Chromium browser cookie DB).
#
# Output: /tmp/cc-statusline-cache/real-usage.env
#   REAL_5H_PCT, REAL_5H_RESET_ISO, REAL_7D_PCT, REAL_7D_RESET_ISO
#   REAL_WEEK_SONNET_PCT (if applicable)
#   REAL_FETCH_OK=1, REAL_REFRESHED_AT, REAL_COOKIE_SRC

CACHE_DIR="/tmp/cc-statusline-cache"
mkdir -p "$CACHE_DIR" 2>/dev/null
CACHE_FILE="$CACHE_DIR/real-usage.env"
TMP_FILE="$CACHE_FILE.tmp.$$"

# Find Python with deps (tls-client + pycookiecheat). Try common locations.
PYTHON=""
for p in "$HOME/miniconda3/bin/python3" "$HOME/anaconda3/bin/python3" "/opt/homebrew/bin/python3" "/usr/local/bin/python3" "python3"; do
    if "$p" -c "import tls_client, pycookiecheat" 2>/dev/null; then
        PYTHON="$p"; break
    fi
done
if [ -z "$PYTHON" ]; then
    echo 'REAL_FETCH_ERROR="missing deps: pip install tls-client pycookiecheat"' > "$CACHE_FILE"
    echo "REAL_REFRESHED_AT=$(date +%s)" >> "$CACHE_FILE"
    exit 0
fi

"$PYTHON" << 'PYEOF' > "$TMP_FILE"
import sys, os, re, json, time
import tls_client
from pycookiecheat import chrome_cookies

CONF = os.path.expanduser('~/.claude/statusline.conf')

# ─── Read sessionKey from Chromium browser cookie DB (auto-rotates) ──
cookies = None
source = ''
for cookie_file, name in [
    ('~/Library/Application Support/Google/Chrome/Default/Cookies', 'Chrome'),
    ('~/Library/Application Support/BraveSoftware/Brave-Browser/Default/Cookies', 'Brave'),
    ('~/Library/Application Support/Microsoft Edge/Default/Cookies', 'Edge'),
    ('~/Library/Application Support/Arc/User Data/Default/Cookies', 'Arc'),
    ('~/Library/Application Support/Chromium/Default/Cookies', 'Chromium'),
]:
    if not os.path.exists(os.path.expanduser(cookie_file)): continue
    try:
        c = chrome_cookies('https://claude.ai', cookie_file=os.path.expanduser(cookie_file))
        if 'sessionKey' in c:
            cookies = c
            source = name
            break
    except Exception:
        continue

# ─── Fallback: manual SESSION_KEY in conf ────────────────────────────
if not cookies or 'sessionKey' not in cookies:
    if os.path.exists(CONF):
        with open(CONF) as f: content = f.read()
        m = re.search(r'^SESSION_KEY="([^"]+)"', content, re.M)
        if m and m.group(1).strip():
            cookies = {'sessionKey': m.group(1).strip()}
            source = 'conf'

if not cookies or 'sessionKey' not in cookies:
    print('REAL_FETCH_ERROR="no sessionKey: log into claude.ai in Chrome/Brave/Edge/Arc"')
    print(f'REAL_REFRESHED_AT={int(time.time())}')
    sys.exit(0)

# ─── Determine org UUID (from conf override or lastActiveOrg cookie) ──
ORG = ''
if os.path.exists(CONF):
    with open(CONF) as f: content = f.read()
    m = re.search(r'^ORG_UUID="([^"]+)"', content, re.M)
    if m and m.group(1).strip(): ORG = m.group(1).strip()
if not ORG:
    ORG = cookies.get('lastActiveOrg', '')
if not ORG:
    print('REAL_FETCH_ERROR="cannot determine org_uuid; visit claude.ai once"')
    print(f'REAL_REFRESHED_AT={int(time.time())}')
    sys.exit(0)

# ─── Build session: tls-client mimicking Chrome 120, with all cookies ─
s = tls_client.Session(client_identifier="chrome_120", random_tls_extension_order=True)
for k, v in cookies.items():
    s.cookies.set(k, v, domain='.claude.ai')

# ─── Auto-detect local HTTP proxy (claude.ai is region-blocked from CN) ─
proxy_url = ''
for port in [6152, 7890, 8888, 1087, 6170]:
    try:
        # Quick TCP probe
        import socket
        with socket.socket() as sk:
            sk.settimeout(0.5)
            sk.connect(('127.0.0.1', port))
        proxy_url = f"http://127.0.0.1:{port}"
        break
    except Exception:
        continue

if proxy_url:
    s.proxies = {"http": proxy_url, "https": proxy_url}

UA = "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/147.0.0.0 Safari/537.36"
headers = {
    "User-Agent": UA,
    "Accept": "application/json",
    "Accept-Language": "en-US,en;q=0.9",
    "Referer": "https://claude.ai/settings/billing",
    "Sec-Fetch-Site": "same-origin",
    "Sec-Fetch-Mode": "cors",
    "Sec-Fetch-Dest": "empty",
}

try:
    r = s.get(f"https://claude.ai/api/organizations/{ORG}/usage", headers=headers, timeout_seconds=8)
except Exception as e:
    print(f'REAL_FETCH_ERROR="request failed: {e}"')
    print(f'REAL_REFRESHED_AT={int(time.time())}')
    sys.exit(0)

if r.status_code != 200:
    print(f'REAL_FETCH_ERROR="HTTP {r.status_code}"')
    print(f'REAL_REFRESHED_AT={int(time.time())}')
    sys.exit(0)

try:
    data = r.json()
except Exception:
    print(f'REAL_FETCH_ERROR="non-json response"')
    print(f'REAL_REFRESHED_AT={int(time.time())}')
    sys.exit(0)

fh = data.get('five_hour', {})
sd = data.get('seven_day', {})
if 'utilization' in fh:    print(f'REAL_5H_PCT={int(round(fh["utilization"]))}')
if 'resets_at' in fh:      print(f'REAL_5H_RESET_ISO="{fh["resets_at"]}"')
if 'utilization' in sd:    print(f'REAL_7D_PCT={int(round(sd["utilization"]))}')
if 'resets_at' in sd:      print(f'REAL_7D_RESET_ISO="{sd["resets_at"]}"')

# Sub-quotas (Sonnet weekly, Design weekly etc., if present)
for k in ['seven_day_opus', 'seven_day_sonnet', 'seven_day_design']:
    if k in data and isinstance(data[k], dict) and 'utilization' in data[k]:
        ku = k.upper().replace('SEVEN_DAY_', 'WEEK_')
        print(f'REAL_{ku}_PCT={int(round(data[k]["utilization"]))}')

print(f'REAL_REFRESHED_AT={int(time.time())}')
print(f'REAL_FETCH_OK=1')
print(f'REAL_COOKIE_SRC="{source}"')
print(f'REAL_PROXY="{proxy_url}"')
PYEOF

[ -s "$TMP_FILE" ] && mv "$TMP_FILE" "$CACHE_FILE" || rm -f "$TMP_FILE"
