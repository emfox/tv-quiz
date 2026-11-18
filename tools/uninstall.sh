#!/usr/bin/env bash
# 卸载：停看门狗、删设备上的文件，可选连开机自启一起删。
#   tools/uninstall.sh             # 删文件 + 停进程，保留自启配置
#   tools/uninstall.sh --with-boot # 连 /vendor/etc/init/tvgate.rc、service.d、init.d 一起删
#   --with-rc 是 --with-boot 的旧名字，等价。
set -uo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
CONF="${CONF:-$ROOT/config/gate.conf}"
ADB="${ADB:-adb}"
HOST=""
WITH_BOOT=0

while [ $# -gt 0 ]; do
  case "$1" in
    --host) HOST="$2"; shift 2 ;;
    --with-boot|--with-rc) WITH_BOOT=1; shift ;;
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

dev_exists() { A shell "[ -e $1 ] && echo y" 2>/dev/null | tr -d '\r' | grep -q y; }
BOOT_MODE="$(A shell "sed -n 's/^BOOT_MODE=//p' $D/config.sh 2>/dev/null | head -1" | tr -d '\r')"

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
  root_run "pkill -f '^/system/bin/sh $D/gate.sh' || true"
else
  echo "无 root，进程会继续跑到下次重启" >&2
fi

if [ "$WITH_BOOT" = "1" ]; then
  if [ -z "$root_mode" ]; then
    echo "无 root，删不掉自启文件（/vendor/etc/init/tvgate.rc、/data/adb/service.d/50-tvquiz.sh）" >&2
  else
    echo "删除开机自启（BOOT_MODE=${BOOT_MODE:-未知}）"
    root_run "rm -f /vendor/etc/init/tvgate.rc /data/adb/service.d/50-tvquiz.sh /system/etc/init.d/99-tvquiz"
  fi
fi

echo "删除 $D"
A shell "rm -rf $D"
A shell "ls -d $D 2>/dev/null || echo '  已删除'" | tr -d '\r'

if [ "$WITH_BOOT" != "1" ] && { dev_exists /vendor/etc/init/tvgate.rc || dev_exists /data/adb/service.d/50-tvquiz.sh; }; then
  echo "自启配置仍在，重启会再拉起一个空跑的服务；用 --with-boot 可一并清掉。"
fi
