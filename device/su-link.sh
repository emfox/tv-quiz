#!/system/bin/sh
# This firmware ships the setuid shell at /factory/su only, and the patched
# init.rc recreates that file on every boot.  Nothing puts it on PATH, so every
# script that just calls `su` fails with "su: not found".  Symlink it into
# /system/bin so the usual command works.
#
# Run through device/root.sh:  device/root.sh -f device/su-link.sh

mount -o remount,rw / 2>&1
ln -sf /factory/su /system/bin/su 2>&1
ls -l /system/bin/su
sync
