#!/usr/bin/env bash
# 看一眼当前状态：服务有没有跑、配置是什么、今天第几次、最近日志、前台是谁。
#   tools/status.sh [--host 192.168.10.60:5555]
set -uo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
CONF="${CONF:-$ROOT/config/gate.conf}"
ADB="${ADB:-adb}"
HOST=""

while [ $# -gt 0 ]; do
  case "$1" in
    --host) HOST="$2"; shift 2 ;;
    -h|--help) sed -n '2,4p' "$0"; exit 0 ;;
    *) echo "未知参数: $1" >&2; exit 2 ;;
  esac
done

conf_get() { sed -n "s/^$1=//p" "$CONF" | head -1 | sed 's/[[:space:]]*#.*$//; s/[[:space:]]*$//'; }
[ -n "$HOST" ] || HOST="$(conf_get ADB_HOST)"
D="$(conf_get DEVICE_DIR)"; D="${D:-/data/local/tmp/tvquiz}"
A() { "$ADB" -s "$HOST" "$@"; }

"$ADB" connect "$HOST" >/dev/null 2>&1
A shell true >/dev/null 2>&1 || { echo "连不上 $HOST" >&2; exit 1; }

echo "=== 服务 ==="
echo "tvgate: $(A shell getprop init.svc.tvgate | tr -d '\r')"
[ "$(A shell "ls $D/pause 2>/dev/null | wc -l" | tr -d '\r')" = "1" ] \
  && echo "pause : 有（闸门暂停中）" || echo "pause : 无（闸门生效中）"

echo "=== 配置 ==="
A shell "grep -E '^(LIMITS|GRADE|N|MODE|PORT|STEP|QUIZ_TIMEOUT|AWAY_RESET|DBG)=' $D/config.sh" | tr -d '\r' | sed 's/^/  /'

echo "=== 当天进度 ==="
A shell "cat $D/state 2>/dev/null" | tr -d '\r' | sed 's/^/  /'
PORT="$(conf_get PORT)"; PORT="${PORT:-8088}"
A shell "/vendor/bin/busybox wget -q -O /dev/null -T 3 http://127.0.0.1:$PORT/index.html && echo '  httpd: 8088 正常' || echo '  httpd: 没起来（下次弹题会自动拉起）'"

echo "=== 前台 ==="
A shell "dumpsys window windows 2>/dev/null | grep -m1 mCurrentFocus" | tr -d '\r' | sed 's/^/  /'

echo "=== 最近日志 ==="
A shell "tail -12 $D/gate.log 2>/dev/null" | tr -d '\r' | sed 's/^/  /'
