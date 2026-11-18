#!/usr/bin/env bash
# Run commands as root on this TV.
#
#   device/root.sh 'id'
#   device/root.sh -t 'mount -o remount,rw /'
#   device/root.sh -f some-script.sh
#   device/root.sh -t -f device/su-link.sh
#   printf 'mount | head -3\n' | device/root.sh
#
# Two channels, and they are NOT equivalent -- pick deliberately.
#
#   su (default)   /factory/su is a setuid copy of mksh, so uid 0, but the process
#                  stays in SELinux domain u:r:shell:s0 and the kernel gives it no
#                  capabilities at all (CapEff=0).  Fast, no polling.  Enough for
#                  dumpsys / am / reading root-owned files / writing under
#                  /data/local/tmp -- anything that only needs uid 0.
#                  It can NOT remount ("not user mountable in fstab"), can NOT
#                  drive init (`stop`/`setprop` check a real uid 0 and see 2000),
#                  and can NOT read a file it does not own: with no
#                  CAP_DAC_OVERRIDE, uid 0 is just a number and the mode bits
#                  still decide.
#                  `-p` is mandatory: mksh calls setuid(getuid()) as soon as it
#                  sees euid != ruid, so without it you land back in uid 2000.
#
#   tvroot (-t)    init service declared in /init.rc, forked by init, so it keeps
#                  every capability and runs in the init domain.  This is the
#                  only way to remount or to touch init services.  Costs a 2 s
#                  poll (the service sleeps between runs).
#
# Commands are pushed as a file instead of being inlined, so quoting and
# multi-line scripts need no escaping.
set -uo pipefail

HERE="$(cd "$(dirname "$0")" && pwd)"
ADB="${ADB:-adb}"
HOST="${TV_HOST:-192.168.10.60:5555}"
CHAN=su
SRC=

usage() { sed -n '2,12p' "$0" | sed 's/^# \{0,1\}//'; }

while [ $# -gt 0 ]; do
  case "$1" in
    -t|--tvroot) CHAN=tvroot; shift ;;
    -f) [ -f "${2:-}" ] || { echo "no such file: ${2:-}" >&2; exit 2; }; SRC=$2; shift 2 ;;
    -h|--help) usage; exit 0 ;;
    --) shift; break ;;
    *) break ;;
  esac
done

A() { "$ADB" -s "$HOST" "$@"; }

TMP="$(mktemp)"
trap 'rm -f "$TMP"' EXIT

if [ -n "$SRC" ]; then
  cat "$SRC" > "$TMP"
elif [ $# -gt 0 ]; then
  printf '%s\n' "$@" > "$TMP"
else
  cat > "$TMP"
fi

"$ADB" connect "$HOST" >/dev/null 2>&1
if ! A shell true >/dev/null 2>&1; then
  echo "cannot reach $HOST" >&2
  exit 1
fi

have_su() { A shell '[ -x /factory/su ] && echo y' 2>/dev/null | tr -d '\r' | grep -q y; }

if [ "$CHAN" = su ]; then
  have_su || { echo "/factory/su not found; retry with -t (tvroot service)" >&2; exit 1; }
  REMOTE=/data/local/tmp/.root.cmd
  A push "$TMP" "$REMOTE" >/dev/null 2>&1 || { echo "push failed" >&2; exit 1; }
  # 644, not 700: the pushed file belongs to uid 2000 and root has no
  # CAP_DAC_OVERRIDE, so only the "other" bits let it be read.
  A shell "chmod 644 $REMOTE" >/dev/null 2>&1
  # Hand the file to the privileged mksh directly.  `-p -c 'sh $REMOTE'` would
  # spawn a second mksh that sees euid != ruid and drops back to uid 2000.
  A shell "/factory/su -p $REMOTE"
  exit $?
fi

# tvroot channel.  The service runs whatever is in tvroot.cmd and deletes it when
# done, so "file gone" is the completion signal -- polling tvroot.out for the
# DONE marker instead would return stale output from the previous run.
REMOTE=/data/local/tmp/tvroot.cmd
OUT=/data/local/tmp/tvroot.out
# The service redirects payload output to a root-only file.  Make it readable at
# the end so readback does not depend on /factory/su existing.
{ cat "$TMP"; echo "chmod 644 $OUT 2>/dev/null"; } > "$TMP.tv"
A push "$TMP.tv" "$REMOTE" >/dev/null 2>&1 || { echo "push failed" >&2; exit 1; }
rm -f "$TMP.tv"

for _ in $(seq 1 30); do
  sleep 1
  if ! A shell "[ -f $REMOTE ] && echo y" 2>/dev/null | tr -d '\r' | grep -q y; then
    A shell "cat $OUT" 2>/dev/null | tr -d '\r' | sed '$d'
    exit 0
  fi
done

echo "!! timed out waiting for tvroot; is init.svc.tvroot running?" >&2
exit 1
