#!/bin/sh
# Install an init service that brings the user's launcher back to front after
# every boot.
#
# TCL's framework relaunches its own boot package (persist.sys.bootpackage)
# regardless of the standard home_activity setting, so the only reliable fix is
# a delayed `am start` once boot has settled.
#
# Needs a root channel on the device. On this TV that is the setuid shell at
# /factory/su (see ../root.sh); without it, remount/cp into /vendor will fail.
#
# Usage: ADB=/path/to/adb TV_HOST=192.168.10.60:5555 ./install.sh

set -eu

ADB=${ADB:-adb}
TV_HOST=${TV_HOST:-192.168.10.60:5555}
DEVICE_DIR=${DEVICE_DIR:-/data/local/tmp}
RC=/vendor/etc/init/lchome.rc
HERE=$(cd "$(dirname "$0")" && pwd)

A="$ADB -s $TV_HOST"

echo "推送脚本到 $DEVICE_DIR"
$A push "$HERE/lchome.sh" "$DEVICE_DIR/lchome.sh" >/dev/null
$A shell "chmod 755 $DEVICE_DIR/lchome.sh"

sed "s|@DEVICE_DIR@|$DEVICE_DIR|g" "$HERE/lchome.rc.in" > "$HERE/lchome.rc.tmp"
$A push "$HERE/lchome.rc.tmp" "$DEVICE_DIR/lchome.rc" >/dev/null
rm -f "$HERE/lchome.rc.tmp"

echo "安装 init 服务到 $RC"
# This firmware has no `su` on PATH; the setuid shell lives at /factory/su and
# mksh drops privileges unless -p is given.
if $A shell "[ -x /factory/su ]" 2>/dev/null | tr -d '\r' | grep -q y; then
    SU="/factory/su -p -c"
else
    SU="su -c"
fi
$A shell "$SU 'mount -o remount,rw /vendor; cp $DEVICE_DIR/lchome.rc $RC; chmod 644 $RC; restorecon $RC; sync'"

if [ "$($A shell "ls $RC 2>/dev/null | wc -l" | tr -d '\r')" = "1" ]; then
    echo "已装 $RC（重启后生效）"
else
    echo "!! 写入 $RC 失败：/vendor 没有 remount 成功，或缺少 root 通道" >&2
    exit 1
fi
