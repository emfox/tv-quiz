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
    -h|--help) sed -n '2,3p' "$0"; exit 0 ;;
    *) echo "未知参数: $1" >&2; exit 2 ;;
  esac
done

conf_get() { sed -n "s/^$1=//p" "$CONF" | head -1 | sed 's/[[:space:]]*#.*$//; s/[[:space:]]*$//'; }
[ -n "$HOST" ] || HOST="$(conf_get ADB_HOST)"
D="$(conf_get DEVICE_DIR)"; D="${D:-/data/local/tmp/tvquiz}"
A() { "$ADB" -s "$HOST" "$@"; }

"$ADB" connect "$HOST" >/dev/null 2>&1
A shell true >/dev/null 2>&1 || { echo "连不上 $HOST" >&2; exit 1; }

dev_exists() { A shell "[ -e $1 ] && echo y" 2>/dev/null | tr -d '\r' | grep -q y; }
dev_cfg() { A shell "sed -n 's/^$1=//p' $D/config.sh 2>/dev/null | head -1" | tr -d '\r' | sed 's/[[:space:]]*#.*$//; s/[[:space:]]*$//'; }

BOOT_MODE="$(dev_cfg BOOT_MODE)"
PORT="$(dev_cfg PORT)"; PORT="${PORT:-8088}"

echo "=== 服务 ==="
echo "自启方式: ${BOOT_MODE:-未设置}"
case "$BOOT_MODE" in
  initrc) if dev_exists /vendor/etc/init/tvgate.rc; then echo "  init 服务: /vendor/etc/init/tvgate.rc 已安装"; else echo "  init 服务: 缺失"; fi
          echo "  tvgate: $(A shell getprop init.svc.tvgate | tr -d '\r')" ;;
  magisk) dev_exists /data/adb/service.d/50-tvquiz.sh && echo "  service.d: 已安装" || echo "  service.d: 缺失" ;;
  initd)  dev_exists /system/etc/init.d/99-tvquiz && echo "  init.d: 已安装" || echo "  init.d: 缺失" ;;
  none)   echo "  无自启（重启后需手动启动）" ;;
esac
# 用 cat 读 cmdline：进程可能刚好退出，`< $p/cmdline` 会让 sh 自己报错
running="$(A shell "for p in /proc/[0-9]*; do c=\$(cat \$p/cmdline 2>/dev/null | tr '\\0' ' '); case \"\$c\" in *$D/gate.sh*) echo yes;; esac; done" | tr -d '\r' | head -1)"
if [ -n "$running" ]; then echo "看门狗  : 在跑"; else echo "看门狗  : 没在跑"; fi
dev_exists "$D/pause" && echo "pause   : 有（闸门暂停中）" || echo "pause   : 无（闸门生效中）"

echo "=== 设备参数 ==="
for k in BROWSER BB ROOT_MODE; do
  v="$(dev_cfg "$k")"
  echo "  $k = ${v:-（未设置）}"
done

echo "=== 闸门配置 ==="
A shell "grep -E '^(LIMITS|GRADE|N|MODE|PORT|STEP|QUIZ_TIMEOUT|AWAY_RESET|DBG)=' $D/config.sh" | tr -d '\r' | sed 's/^/  /'

echo "=== 当天进度 ==="
A shell "cat $D/state 2>/dev/null" | tr -d '\r' | sed 's/^/  /'

echo "=== 答题页服务 ==="
BB="$(dev_cfg BB)"
case "$BB" in
  ""|auto)
    BB=""
    for c in /vendor/bin/busybox /data/adb/magisk/busybox /data/adb/ksu/bin/busybox /system/xbin/busybox /system/bin/busybox; do
      dev_exists "$c" && { BB="$c"; break; }
    done ;;
esac
if [ -n "$BB" ]; then
  if A shell "$BB wget -q -O /dev/null -T 3 http://127.0.0.1:$PORT/index.html && echo ok || echo fail" | tr -d '\r' | grep -q '^ok'; then
    echo "  httpd: $PORT 正常（$BB）"
  else
    echo "  httpd: 没起来（下次弹题会自动拉起）"
  fi
else
  echo "  busybox: 未找到，httpd 起不来（装一个 busybox 模块，或在配置里写 BB=完整路径）"
fi

echo "=== 前台 ==="
A shell '
  l=$(dumpsys window windows 2>/dev/null | grep mCurrentFocus= | head -1)
  [ -z "$l" ] && l=$(dumpsys window 2>/dev/null | grep mCurrentFocus= | head -1)
  echo "${l:-（空，可能息屏）}"
' | tr -d '\r' | sed 's/^/  /'

echo "=== 最近日志 ==="
A shell "tail -12 $D/gate.log 2>/dev/null" | tr -d '\r' | sed 's/^/  /'
