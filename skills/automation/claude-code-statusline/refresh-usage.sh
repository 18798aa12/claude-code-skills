#!/bin/bash
# 后台跑 ccusage, 把 5h block + 滚动 7d 数据写到 cache 文件
# launchd 每 60s 调用一次, statusline.sh 永远只读这个 cache

CACHE_DIR="/tmp/cc-statusline-cache"
mkdir -p "$CACHE_DIR" 2>/dev/null
CACHE_FILE="$CACHE_DIR/usage.env"
TMP_FILE="$CACHE_FILE.tmp.$$"

# Auto-detect Node install (nvm latest, homebrew, system) so npx is found under launchd
NODE_BIN="$(ls -dt $HOME/.nvm/versions/node/*/bin 2>/dev/null | head -1)"
export PATH="${NODE_BIN}:/usr/local/bin:/opt/homebrew/bin:/usr/bin:/bin:$PATH"

SINCE=$(date -v-6d +%Y%m%d 2>/dev/null || date -d '6 days ago' +%Y%m%d)
UNTIL=$(date +%Y%m%d)

# 一次拉 blocks (5h + 7d 滚动重置都算它), daily (7d 累加)
BLOCKS_JSON=$(npx -y ccusage blocks --json --offline 2>/dev/null)
DAILY_JSON=$(npx -y ccusage daily --since $SINCE --until $UNTIL --json --offline 2>/dev/null)

{
    # ─── 5h 当前 block + 7d rolling reset (用 blocks 的 startTime 算) ─
    echo "$BLOCKS_JSON" | python3 -c "
import json, sys
from datetime import datetime, timedelta
try:
    d = json.load(sys.stdin)
    now = datetime.now().astimezone()
    # 5h 当前
    active = [b for b in d.get('blocks', []) if b.get('isActive')]
    if active:
        b = active[0]
        tc = b.get('tokenCounts', {})
        cost = b.get('costUSD', 0)
        rem = b.get('projection', {}).get('remainingMinutes', 0)
        ti_raw = tc.get('inputTokens', 0)
        ti_cw = tc.get('cacheCreationInputTokens', 0)
        ti_cr = tc.get('cacheReadInputTokens', 0)
        ti = ti_raw + ti_cw + ti_cr
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
        print(f'BLOCK_IN_RAW={ti_raw}')
        print(f'BLOCK_CACHE_WRITE={ti_cw}')
        print(f'BLOCK_CACHE_READ={ti_cr}')
        print(f'BLOCK_OUT={to}')
        print(f'BLOCK_ENTRIES={entries}')
    else:
        print('BLOCK_COST=0.00\nBLOCK_REMAIN_MIN=0\nBLOCK_RESET=\"--:--\"\nBLOCK_IN=0\nBLOCK_OUT=0\nBLOCK_ENTRIES=0')

    # 7d 滚动重置 = 过去 7 天最早 non-gap block startTime + 7d
    seven_ago = now - timedelta(days=7)
    recent_blocks = []
    for b in d.get('blocks', []):
        if b.get('isGap'): continue
        try:
            st = datetime.fromisoformat(b.get('startTime','').replace('Z','+00:00')).astimezone()
            if st >= seven_ago:
                recent_blocks.append(st)
        except: pass
    if recent_blocks:
        earliest = min(recent_blocks)
        next_drop = earliest + timedelta(days=7)
        roll_str = next_drop.strftime('%m-%d %H:%M')
        secs = max(0, int((next_drop - now).total_seconds()))
        d = secs // 86400; h = (secs % 86400) // 3600; m = (secs % 3600) // 60
        if d > 0:
            left = f'{d}d{h:02d}h{m:02d}m'
        else:
            left = f'{h}h{m:02d}m'
        print(f'WEEK_RESET=\"{roll_str}\"')
        print(f'WEEK_LEFT=\"{left}\"')
    else:
        print('WEEK_RESET=\"--\"')
        print('WEEK_LEFT=\"0m\"')
except Exception:
    print('BLOCK_COST=0.00\nBLOCK_REMAIN_MIN=0\nBLOCK_RESET=\"--:--\"\nBLOCK_IN=0\nBLOCK_OUT=0\nBLOCK_ENTRIES=0\nWEEK_RESET=\"--\"\nWEEK_LEFT=\"0h\"')
"
    # ─── 7d 累加 (daily) ─────────────────────────────────────────────
    echo "$DAILY_JSON" | python3 -c "
import json, sys
try:
    d = json.load(sys.stdin)
    days = d.get('daily', [])
    cost = sum(x.get('totalCost', 0) for x in days)
    ti_raw = sum(x.get('inputTokens', 0) for x in days)
    ti_cw = sum(x.get('cacheCreationTokens', 0) for x in days)
    ti_cr = sum(x.get('cacheReadTokens', 0) for x in days)
    ti = ti_raw + ti_cw + ti_cr
    to = sum(x.get('outputTokens', 0) for x in days)
    print(f'WEEK_COST={cost:.2f}')
    print(f'WEEK_IN={ti}')
    print(f'WEEK_IN_RAW={ti_raw}')
    print(f'WEEK_CACHE_WRITE={ti_cw}')
    print(f'WEEK_CACHE_READ={ti_cr}')
    print(f'WEEK_OUT={to}')
    print(f'WEEK_TOTAL={ti+to}')
except Exception:
    print('WEEK_COST=0.00\nWEEK_IN=0\nWEEK_OUT=0\nWEEK_TOTAL=0')
"
    echo "REFRESHED_AT=$(date +%s)"
} > "$TMP_FILE" 2>/dev/null

[ -s "$TMP_FILE" ] && mv "$TMP_FILE" "$CACHE_FILE" || rm -f "$TMP_FILE"
