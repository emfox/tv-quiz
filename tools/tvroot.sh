#!/usr/bin/env bash
# 通过 init 服务 tvroot 以 root 身份执行命令并回读输出。
# 前提：机型已刷过带 tvroot 服务的固件（见 README「root 从哪来」）。
#
#   tools/tvroot.sh 'id'
#   TV_HOST=192.168.1.9:5555 tools/tvroot.sh 'mount | head -3'
#
# 注意：回读轮询上限 15 秒，命令里不要放长 sleep。
set -u
ADB="${ADB:-adb}"
HOST="${TV_HOST:-192.168.10.60:5555}"
TMP="$(mktemp /tmp/tvroot.XXXXXX)"

if [ $# -gt 0 ]; then
  printf '%s\n' "$@" > "$TMP"
else
  cat > "$TMP"
fi

"$ADB" connect "$HOST" >/dev/null 2>&1
"$ADB" -s "$HOST" shell "rm -f /data/local/tmp/tvroot.out" >/dev/null 2>&1
"$ADB" -s "$HOST" push "$TMP" /data/local/tmp/tvroot.cmd >/dev/null 2>&1
rm -f "$TMP"

for _ in $(seq 1 15); do
  sleep 1
  if "$ADB" -s "$HOST" shell "/factory/su -p -c 'grep -c DONE /data/local/tmp/tvroot.out'" 2>/dev/null \
      | tr -d '\r' | grep -q '^1$'; then
    "$ADB" -s "$HOST" shell "/factory/su -p -c 'cat /data/local/tmp/tvroot.out'" 2>/dev/null \
      | tr -d '\r' | sed '$d'
    exit 0
  fi
done

echo "!! timeout waiting for tvroot; is init.svc.tvroot running?" >&2
exit 1
