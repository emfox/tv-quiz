#!/usr/bin/env bash
# 假 adb，给 tests/t-install.sh 用。行为由 FAKE_STATE 目录里的标记文件控制：
#   vendor_init  有 /vendor/etc/init    service_d  有 /data/adb/service.d
#   init_d       有 /system/etc/init.d  rc_exists  init 服务已经装过
#   no_root      su 不可用
# 推上来的文件落在 FAKE_PUSHED，调用记录追加到 FAKE_LOG。
set -u

LOG=${FAKE_LOG:-/dev/null}
STATE=${FAKE_STATE:?FAKE_STATE 未设置}
PUSHED=${FAKE_PUSHED:?FAKE_PUSHED 未设置}
MODEL=${FAKE_MODEL:-tcl_m7642}

echo "adb $*" >> "$LOG"

[ "${1:-}" = "connect" ] && exit 0
[ "${1:-}" = "-s" ] && shift 2
sub="${1:-}"
shift || true

case "$sub" in
  push)
    # 用目标文件名（源是 mktemp 出来的临时文件，名字对不上）
    cp "$1" "$PUSHED/$(basename "$2")" 2>/dev/null
    exit 0
    ;;
  shell)
    cmd="$*"
    case "$cmd" in
      true) exit 0 ;;
      *ro.product.model*)        echo "$MODEL"; exit 0 ;;
      *ro.build.version.release*) echo 11; exit 0 ;;
      *init.svc.tvroot*)         echo stopped; exit 0 ;;
      *init.svc.tvgate*)         echo running; exit 0 ;;
      *"pm list packages"*)      cat "$STATE/packages" 2>/dev/null; exit 0 ;;
      *"su -c true"*)            [ -f "$STATE/no_root" ] && exit 1; exit 0 ;;
      *"su -c"*)                 echo "root: $cmd" >> "$LOG"; exit 0 ;;
      *"/data/adb/service.d ]"*) [ -f "$STATE/service_d" ] && echo y; exit 0 ;;
      *"/vendor/etc/init ]"*)    [ -f "$STATE/vendor_init" ] && echo y; exit 0 ;;
      *"/system/etc/init.d ]"*)  [ -f "$STATE/init_d" ] && echo y; exit 0 ;;
      *tvgate.rc*wc*)            [ -f "$STATE/rc_exists" ] && echo 1 || echo 0; exit 0 ;;
      *"ls "*)                   echo "config.sh"; exit 0 ;;
      *) exit 0 ;;
    esac
    ;;
esac
exit 0
