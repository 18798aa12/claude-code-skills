#!/bin/bash
# Claude Code statusline — 2 行, 永不阻塞, 含百分比 + 进度条 + 重置时间
#
# Line 1: 👤user @ cwd  ⎇branch*  model  🕐time  🧠ctx:N%  ✓todos:N
# Line 2: ⚡5h ▰▰▱▱▱ 19% $30/$160 · 重置04:00(3h46) · ↓45M↑89k │ 📅7d ▱▱▱▱▱ 4% $46/$1120 · 重置05-21(6d) · ↓63M↑145k Σ63M
#
# ⚠️ Anthropic 不公开 Pro/Max 真实限额, USD 是 ccusage 估算 (按 API 标价反推), 仅参考.
# 真限额是 token throughput + 消息数 + 突发频率综合, 通常 USD 估比真触发率偏低.

input=$(cat)
CACHE_FILE="/tmp/cc-statusline-cache/usage.env"
REAL_CACHE="/tmp/cc-statusline-cache/real-usage.env"
CONF_FILE="$HOME/.claude/statusline.conf"

CC_PLAN=max20
[ -f "$CONF_FILE" ] && source "$CONF_FILE" 2>/dev/null

case "$CC_PLAN" in
    pro)    LIMIT_5H=8;    LIMIT_7D=50 ;;
    max5)   LIMIT_5H=40;   LIMIT_7D=280 ;;
    max20)  LIMIT_5H=160;  LIMIT_7D=1120 ;;
    *)      LIMIT_5H=160;  LIMIT_7D=1120 ;;
esac

# ─── Parse input JSON ────────────────────────────────────────────────
user=$(whoami)
cwd=$(echo "$input" | jq -r '.workspace.current_dir // .cwd // "."' | sed "s|$HOME|~|g")
model=$(echo "$input" | jq -r '.model.display_name // "?"')
transcript=$(echo "$input" | jq -r '.transcript_path // ""')
remaining=$(echo "$input" | jq -r '.context_window.remaining_percentage // empty')
time_now=$(date +%H:%M)

work_dir=$(echo "$input" | jq -r '.workspace.current_dir // .cwd // "."')
cd "$work_dir" 2>/dev/null
branch=$(git rev-parse --abbrev-ref HEAD 2>/dev/null || true)
status=''
[ -n "$branch" ] && [ -n "$(git status --porcelain 2>/dev/null)" ] && status='*'

todo_count=0
if [ -f "$transcript" ]; then
    raw=$(tail -c 1048576 "$transcript" 2>/dev/null | grep -c '"type":"todo"' 2>/dev/null | tr -d '[:space:]')
    [ -n "$raw" ] && todo_count="$raw"
fi

# ─── 读 ccusage cache (token 数 in/out + 缓存细分) ───────────────────
BLOCK_COST=0.00; BLOCK_REMAIN_MIN=0; BLOCK_RESET="--:--"
BLOCK_IN=0; BLOCK_IN_RAW=0; BLOCK_CACHE_WRITE=0; BLOCK_CACHE_READ=0
BLOCK_OUT=0; BLOCK_ENTRIES=0
WEEK_COST=0.00; WEEK_IN=0; WEEK_IN_RAW=0; WEEK_CACHE_WRITE=0; WEEK_CACHE_READ=0
WEEK_OUT=0; WEEK_TOTAL=0; WEEK_RESET="--"; WEEK_LEFT="0h"
REFRESHED_AT=0
[ -f "$CACHE_FILE" ] && source "$CACHE_FILE" 2>/dev/null

# ─── 读 real-usage cache (Anthropic 真实 % + 重置, 优先用) ───────────
REAL_5H_PCT=""; REAL_5H_RESET_ISO=""; REAL_7D_PCT=""; REAL_7D_RESET_ISO=""
REAL_WEEK_SONNET_PCT=""; REAL_REFRESHED_AT=0; REAL_FETCH_OK=0
[ -f "$REAL_CACHE" ] && source "$REAL_CACHE" 2>/dev/null

now=$(date +%s)
if [ "$((now - REFRESHED_AT))" -gt 90 ]; then
    nohup ~/.claude/refresh-usage.sh </dev/null >/dev/null 2>&1 &
    disown 2>/dev/null || true
fi
if [ "$((now - REAL_REFRESHED_AT))" -gt 90 ]; then
    nohup ~/.claude/fetch-real-usage.sh </dev/null >/dev/null 2>&1 &
    disown 2>/dev/null || true
fi

# ─── 重置时刻 + 实时剩余 (优先真实 ISO 时间) ──────────────────────────
# 5h
if [ -n "$REAL_5H_RESET_ISO" ]; then
    parsed=$(python3 -c "
from datetime import datetime
try:
    dt = datetime.fromisoformat('$REAL_5H_RESET_ISO').astimezone()
    secs = max(0, int((dt - datetime.now().astimezone()).total_seconds()))
    h = secs//3600; m = (secs%3600)//60
    left = f'{h}h{m:02d}m' if h else f'{m}m'
    print(f'{dt.strftime(\"%H:%M\")}|{left}')
except Exception as e:
    print('|')
" 2>/dev/null)
    BLOCK_RESET=$(echo "$parsed" | cut -d'|' -f1)
    BLOCK_REMAIN_LIVE=$(echo "$parsed" | cut -d'|' -f2)
elif [ "$BLOCK_RESET" != "--:--" ] && [ -n "$BLOCK_RESET" ]; then
    BLOCK_REMAIN_LIVE=$(python3 -c "
from datetime import datetime, timedelta
now = datetime.now()
hh, mm = '$BLOCK_RESET'.split(':')
target = now.replace(hour=int(hh), minute=int(mm), second=0, microsecond=0)
if target <= now: target += timedelta(days=1)
secs = int((target - now).total_seconds())
h = secs // 3600; m = (secs % 3600) // 60
print(f'{h}h{m:02d}m' if h else f'{m}m')
" 2>/dev/null)
fi
[ -z "$BLOCK_REMAIN_LIVE" ] && BLOCK_REMAIN_LIVE="$(printf '%dh%02dm' $((BLOCK_REMAIN_MIN/60)) $((BLOCK_REMAIN_MIN%60)))"
[ -z "$BLOCK_RESET" ] && BLOCK_RESET="--:--"

# 7d
if [ -n "$REAL_7D_RESET_ISO" ]; then
    parsed=$(python3 -c "
from datetime import datetime
try:
    dt = datetime.fromisoformat('$REAL_7D_RESET_ISO').astimezone()
    secs = max(0, int((dt - datetime.now().astimezone()).total_seconds()))
    d = secs//86400; h = (secs%86400)//3600; m = (secs%3600)//60
    if d: left = f'{d}d{h:02d}h{m:02d}m'
    else: left = f'{h}h{m:02d}m' if h else f'{m}m'
    print(f'{dt.strftime(\"%m-%d %H:%M\")}|{left}')
except Exception as e:
    print('|')
" 2>/dev/null)
    WEEK_RESET=$(echo "$parsed" | cut -d'|' -f1)
    WEEK_LEFT_LIVE=$(echo "$parsed" | cut -d'|' -f2)
elif [ "$WEEK_RESET" != "--" ] && [ -n "$WEEK_RESET" ]; then
    WEEK_LEFT_LIVE=$(python3 -c "
from datetime import datetime
now = datetime.now()
try:
    s = '$WEEK_RESET'
    md, hm = s.split(' '); mo, day = md.split('-'); hh, mm = hm.split(':')
    target = now.replace(month=int(mo), day=int(day), hour=int(hh), minute=int(mm), second=0, microsecond=0)
    if target < now: target = target.replace(year=target.year+1)
    secs = max(0, int((target - now).total_seconds()))
    d = secs // 86400; h = (secs % 86400) // 3600; m = (secs % 3600) // 60
    print(f'{d}d{h:02d}h{m:02d}m' if d else f'{h}h{m:02d}m')
except Exception: print('')
" 2>/dev/null)
fi
[ -z "$WEEK_LEFT_LIVE" ] && WEEK_LEFT_LIVE="$WEEK_LEFT"
[ -z "$WEEK_RESET" ] && WEEK_RESET="--"

# ─── 百分比: 优先真实, 没有再用 ccusage USD 估算 ─────────────────────
SOURCE_TAG=""
if [ "$REAL_FETCH_OK" = "1" ] && [ -n "$REAL_5H_PCT" ]; then
    pct_5h=$REAL_5H_PCT
    pct_7d=$REAL_7D_PCT
    SOURCE_TAG="✓"  # 真实数据
else
    pct_5h=$(awk -v u="$BLOCK_COST" -v l="$LIMIT_5H" 'BEGIN{p=u*100/l; if(p>999) p=999; printf "%.0f", p}')
    pct_7d=$(awk -v u="$WEEK_COST" -v l="$LIMIT_7D" 'BEGIN{p=u*100/l; if(p>999) p=999; printf "%.0f", p}')
    SOURCE_TAG="≈"  # 估算
fi

# ─── 进度条 ──────────────────────────────────────────────────────────
make_bar() {
    p=$1
    [ "$p" -gt 100 ] 2>/dev/null && p=100
    filled=$(( p / 20 ))
    [ "$filled" -gt 5 ] && filled=5
    bar=""
    for i in 1 2 3 4 5; do
        if [ "$i" -le "$filled" ]; then bar="${bar}▰"; else bar="${bar}▱"; fi
    done
    echo "$bar"
}

bar_5h=$(make_bar $pct_5h)
bar_7d=$(make_bar $pct_7d)

# ─── Format helpers ──────────────────────────────────────────────────
fmt_n() {
    n=${1:-0}
    if [ "$n" -ge 1000000 ] 2>/dev/null; then
        awk -v x="$n" 'BEGIN{printf "%.1fM", x/1000000}'
    elif [ "$n" -ge 1000 ] 2>/dev/null; then
        awk -v x="$n" 'BEGIN{printf "%.1fk", x/1000}'
    else
        printf "%d" "$n"
    fi
}

fmt_min() {
    m=${1:-0}
    if [ "$m" -ge 60 ] 2>/dev/null; then
        h=$(( m / 60 )); rest=$(( m % 60 ))
        printf "%dh%02dm" "$h" "$rest"
    else
        printf "%dm" "$m"
    fi
}

color_pct() {
    awk -v p="$1" 'BEGIN{ if(p+0<50) print "G"; else if(p+0<80) print "Y"; else print "RD" }'
}

# ─── Colors ──────────────────────────────────────────────────────────
B=$'\033[38;2;79;156;249m'
G=$'\033[38;2;120;200;120m'
Y=$'\033[38;2;240;180;80m'
M=$'\033[38;2;180;130;240m'
C=$'\033[38;2;90;200;220m'
W=$'\033[38;2;240;240;240m'
T=$'\033[38;2;120;120;140m'
RD=$'\033[38;2;240;90;90m'
DM=$'\033[2m'
BD=$'\033[1m'
R=$'\033[0m'

case $(color_pct "$pct_5h") in G) C5=$G;; Y) C5=$Y;; *) C5=$RD;; esac
case $(color_pct "$pct_7d") in G) C7=$G;; Y) C7=$Y;; *) C7=$RD;; esac

ctx_color=""
if [ -n "$remaining" ]; then
    case $(awk -v c="$remaining" 'BEGIN{ if(c+0>50) print "G"; else if(c+0>20) print "Y"; else print "RD" }') in
        G) ctx_color=$G;; Y) ctx_color=$Y;; *) ctx_color=$RD;;
    esac
fi

SEP="${T}│${R}"

# ─── Line 1: 基础信息 ────────────────────────────────────────────────
printf "${BD}${C}%s${R}${T}@${R}${B}%s${R}" "$user" "$cwd"
[ -n "$branch" ] && printf " ${G}⎇ %s${Y}%s${R}" "$branch" "$status"
printf " ${T}%s${R} ${DM}${W}%s${R}" "$model" "$time_now"
[ -n "$remaining" ] && printf " ${T}🧠${R}${ctx_color}${remaining}%%${R}"
[ "$todo_count" -gt 0 ] 2>/dev/null && printf " ${T}✓${R}${C}${todo_count}${R}"
printf "\n"

# ─── Line 2: 5h + 7d 用量 ────────────────────────────────────────────
printf "${T}⚡5h${SOURCE_TAG}${R} ${C5}%s${R} ${BD}${C5}%s%%${R}" "$bar_5h" "$pct_5h"
printf " ${DM}\$${BLOCK_COST}${R}"
printf " ${T}·${R} ${T}↻${R}${BD}${W}${BLOCK_RESET}${R}${DM}(剩${BLOCK_REMAIN_LIVE})${R}"
BLOCK_CACHE=$(( BLOCK_CACHE_READ + BLOCK_CACHE_WRITE ))
printf " ${T}·${R} ${DM}in:${R}${G}%s${R} ${DM}💾${R}${C}%s${R} ${DM}out:${R}${Y}%s${R}" "$(fmt_n $BLOCK_IN_RAW)" "$(fmt_n $BLOCK_CACHE)" "$(fmt_n $BLOCK_OUT)"
printf "  ${SEP}  "
printf "${T}📅7d${SOURCE_TAG}${R} ${C7}%s${R} ${BD}${C7}%s%%${R}" "$bar_7d" "$pct_7d"
printf " ${DM}\$${WEEK_COST}${R}"
printf " ${T}·${R} ${T}↻${R}${BD}${W}${WEEK_RESET}${R}${DM}(剩${WEEK_LEFT_LIVE})${R}"
WEEK_CACHE=$(( WEEK_CACHE_READ + WEEK_CACHE_WRITE ))
printf " ${T}·${R} ${DM}in:${R}${G}%s${R} ${DM}💾${R}${C}%s${R} ${DM}out:${R}${Y}%s${R}" "$(fmt_n $WEEK_IN_RAW)" "$(fmt_n $WEEK_CACHE)" "$(fmt_n $WEEK_OUT)"
printf " ${T}·${R} ${DM}Σ${R}${M}%s${R}\n" "$(fmt_n $WEEK_TOTAL)"
