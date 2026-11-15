#!/usr/bin/env bash
# 卸载：停看门狗、删设备上的文件，可选连 init 服务一起删。
#   tools/uninstall.sh             # 删文件 + 停进程，保留 init 服务定义
#   tools/uninstall.sh --with-rc   # 连 /vendor/etc/init/tvgate.rc 一起删
set -uo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
CONF="${CONF:-$ROOT/config/gate.conf}"
ADB="${ADB:-adb}"
HOST=""
WITH_RC=0

while [ $# -gt 0 ]; do
  case "$1" in
    --host) HOST="$2"; shift 2 ;;
    --with-rc) WITH_RC=1; shift ;;
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

root_mode=""
if [ "$(A shell getprop init.svc.tvroot 2>/dev/null | tr -d '\r')" = "running" ] && [ -x "$ROOT/tools/tvroot.sh" ]; then
  root_mode="tvroot"
elif A shell "su -c true" >/dev/null 2>&1; then
  root_mode="su"
fi
root_run() {
  case "$root_mode" in
    tvroot) TV_HOST="$HOST" "$ROOT/tools/tvroot.sh" "$1" ;;
    su) A shell "su -c '$1'" ;;
    *) return 3 ;;
  esac
}

echo "停止看门狗"
if [ -n "$root_mode" ]; then
  root_run "for p in /proc/[0-9]*; do c=\$(cat \$p/cmdline 2>/dev/null | tr '\\000' ' '); case \"\$c\" in *$D/gate.sh*) kill \${p#/proc/};; esac; done"
else
  echo "无 root，进程会继续跑到下次重启" >&2
fi

if [ "$WITH_RC" = "1" ] && [ -n "$root_mode" ]; then
  echo "删除 init 服务 /vendor/etc/init/tvgate.rc"
  root_run "rm -f /vendor/etc/init/tvgate.rc"
fi

echo "删除 $D"
A shell "rm -rf $D"
A shell "ls -d $D 2>/dev/null || echo '  已删除'" | tr -d '\r'

echo "完成。init 服务定义仍在时，重启会再拉起一个空跑的服务，用 --with-rc 可一并清掉。"
