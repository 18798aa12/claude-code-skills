#!/bin/bash
# Run ccusage to extract 5h block + 7d rolling token/cost data → cache file
# Called by launchd every 60s. statusline.sh only reads the cache (instant).

CACHE_DIR="/tmp/cc-statusline-cache"
mkdir -p "$CACHE_DIR" 2>/dev/null
CACHE_FILE="$CACHE_DIR/usage.env"
TMP_FILE="$CACHE_FILE.tmp.$$"

# Add common Node install paths so npx is found under launchd
export PATH="/usr/local/bin:/opt/homebrew/bin:$HOME/.nvm/versions/node/$(ls $HOME/.nvm/versions/node 2>/dev/null | tail -1)/bin:/usr/bin:/bin:$PATH"

SINCE=$(date -v-6d +%Y%m%d 2>/dev/null || date -d '6 days ago' +%Y%m%d)
UNTIL=$(date +%Y%m%d)

BLOCKS_JSON=$(npx -y ccusage blocks --json --offline 2>/dev/null)
DAILY_JSON=$(npx -y ccusage daily --since $SINCE --until $UNTIL --json --offline 2>/dev/null)

{
    echo "$BLOCKS_JSON" | python3 -c "
import json, sys
from datetime import datetime, timedelta
try:
    d = json.load(sys.stdin)
    now = datetime.now().astimezone()
    active = [b for b in d.get('blocks', []) if b.get('isActive')]
    if active:
        b = active[0]
        tc = b.get('tokenCounts', {})
        cost = b.get('costUSD', 0)
        rem = b.get('projection', {}).get('remainingMinutes', 0)
        ti = tc.get('inputTokens', 0) + tc.get('cacheCreationInputTokens', 0) + tc.get('cacheReadInputTokens', 0)
        to = tc.get('outputTokens', 0)
        entries = b.get('entries', 0)
        end_iso = b.get('endTime', '')
        try:
            end_local = datetime.fromisoformat(end_iso.replace('Z', '+00:00')).astimezone()
            end_str = end_local.strftime('%H:%M')
        except: end_str = '??:??'
        print(f'BLOCK_COST={cost:.2f}')
        print(f'BLOCK_REMAIN_MIN={rem}')
        print(f'BLOCK_RESET=\"{end_str}\"')
        print(f'BLOCK_IN={ti}')
        print(f'BLOCK_OUT={to}')
        print(f'BLOCK_ENTRIES={entries}')
    else:
        print('BLOCK_COST=0.00\nBLOCK_REMAIN_MIN=0\nBLOCK_RESET=\"--:--\"\nBLOCK_IN=0\nBLOCK_OUT=0\nBLOCK_ENTRIES=0')

    seven_ago = now - timedelta(days=7)
    recent = []
    for b in d.get('blocks', []):
        if b.get('isGap'): continue
        try:
            st = datetime.fromisoformat(b.get('startTime','').replace('Z','+00:00')).astimezone()
            if st >= seven_ago: recent.append(st)
        except: pass
    if recent:
        earliest = min(recent)
        next_drop = earliest + timedelta(days=7)
        roll_str = next_drop.strftime('%m-%d %H:%M')
        secs = max(0, int((next_drop - now).total_seconds()))
        d_ = secs // 86400; h = (secs % 86400) // 3600; m = (secs % 3600) // 60
        left = f'{d_}d{h:02d}h{m:02d}m' if d_ else f'{h}h{m:02d}m'
        print(f'WEEK_RESET=\"{roll_str}\"')
        print(f'WEEK_LEFT=\"{left}\"')
    else:
        print('WEEK_RESET=\"--\"\nWEEK_LEFT=\"0m\"')
except Exception:
    print('BLOCK_COST=0.00\nBLOCK_REMAIN_MIN=0\nBLOCK_RESET=\"--:--\"\nBLOCK_IN=0\nBLOCK_OUT=0\nBLOCK_ENTRIES=0\nWEEK_RESET=\"--\"\nWEEK_LEFT=\"0m\"')
"
    echo "$DAILY_JSON" | python3 -c "
import json, sys
try:
    d = json.load(sys.stdin)
    days = d.get('daily', [])
    cost = sum(x.get('totalCost', 0) for x in days)
    ti = sum(x.get('inputTokens', 0) + x.get('cacheCreationTokens', 0) + x.get('cacheReadTokens', 0) for x in days)
    to = sum(x.get('outputTokens', 0) for x in days)
    print(f'WEEK_COST={cost:.2f}\nWEEK_IN={ti}\nWEEK_OUT={to}\nWEEK_TOTAL={ti+to}')
except Exception:
    print('WEEK_COST=0.00\nWEEK_IN=0\nWEEK_OUT=0\nWEEK_TOTAL=0')
"
    echo "REFRESHED_AT=$(date +%s)"
} > "$TMP_FILE" 2>/dev/null

[ -s "$TMP_FILE" ] && mv "$TMP_FILE" "$CACHE_FILE" || rm -f "$TMP_FILE"
