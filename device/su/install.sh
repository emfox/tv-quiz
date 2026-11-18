#!/usr/bin/env bash
# Build the su wrapper and install it as a setuid binary at /system/bin/su.
#
#   device/su/install.sh
#
# Needs arm-linux-gnueabihf-gcc on the build host, and the tvroot channel on the
# device (installing means remounting / read-write).
#
# /factory/su is deliberately left alone: init rebuilds it from /system/bin/sh
# on every boot, and device/root.sh reaches it by absolute path, so a broken
# wrapper can never lock you out of the box.
set -euo pipefail

HERE="$(cd "$(dirname "$0")" && pwd)"
ADB="${ADB:-adb}"
HOST="${TV_HOST:-192.168.10.60:5555}"

command -v arm-linux-gnueabihf-gcc >/dev/null 2>&1 || {
  echo "need arm-linux-gnueabihf-gcc (apt install gcc-arm-linux-gnueabihf)" >&2
  exit 1
}

make -C "$HERE" >/dev/null
"$ADB" -s "$HOST" push "$HERE/su" /data/local/tmp/su.arm >/dev/null

ADB="$ADB" TV_HOST="$HOST" "$HERE/../root.sh" -t '
mount -o remount,rw / || exit 1
trap "mount -o remount,ro /" EXIT
cp /data/local/tmp/su.arm /system/bin/su.new || exit 1
chown root:root /system/bin/su.new
chmod 6755 /system/bin/su.new
restorecon /system/bin/su.new
mv -f /system/bin/su.new /system/bin/su || exit 1
sync
ls -lZ /system/bin/su
'
