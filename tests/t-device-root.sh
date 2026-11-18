#!/usr/bin/env bash
# device/root.sh：通道选择、参数拼装、完成信号。全部离线，用假 adb。
set -u
. "$(dirname "$0")/lib.sh"

T=$(mktemp -d)
trap 'rm -rf "$T"' EXIT
LOG="$T/calls.log"
: > "$LOG"
export FAKE_LOG="$LOG" FAKE_T="$T"
export ADB="$T/adb"
export TV_HOST=fake:5555

cat > "$T/adb" <<'FAKE'
#!/usr/bin/env bash
printf 'ARGV %s\n' "$*" >> "$FAKE_LOG"
[ "${1:-}" = connect ] && exit 0
[ "${1:-}" = -s ] && shift 2
sub=${1:-}; shift || true
case "$sub" in
  true) exit 0 ;;
  push) cp "$1" "$FAKE_T/$(basename "$2")"; exit 0 ;;
  shell)
    cmd=$*
    case "$cmd" in
      chmod*) exit 0 ;;
      *"-x /factory/su"*) [ -f "$FAKE_T/no_su" ] || echo y; exit 0 ;;
      *"[ -f /data/local/tmp/tvroot.cmd ]"*)
        n=$(cat "$FAKE_T/poll" 2>/dev/null || echo 0); n=$((n + 1))
        echo "$n" > "$FAKE_T/poll"
        [ "$n" -le 1 ] && echo y
        exit 0 ;;
      *"cat /data/local/tmp/tvroot.out"*) printf 'payload-out\nDONE\n'; exit 0 ;;
      *"/factory/su -p /data/local/tmp/.root.cmd"*)
        echo "SU-RAN"; sh "$FAKE_T/.root.cmd"; exit 0 ;;
      *) exit 0 ;;
    esac ;;
esac
exit 0
FAKE
chmod +x "$T/adb"
R="$ROOT/device/root.sh"

# --- 默认走 su 通道 --------------------------------------------------------
out=$("$R" 'echo hi' 2>&1)
eq "单命令：执行结果" "SU-RAN
hi" "$out"
eq "单命令：推送内容" "echo hi" "$(cat "$T/.root.cmd")"
yes "单命令：交给特权 mksh，不再套一层 sh" \
    "grep -q 'shell /factory/su -p /data/local/tmp/.root.cmd' '$LOG'"
no "单命令：没有会降权的 -c 'sh ...'" "grep -qF -- \"-c 'sh \" '$LOG'"
yes "推送后改成 644（root 没有 DAC_OVERRIDE，700 它自己都读不了）" \
    "grep -q 'shell chmod 644 /data/local/tmp/.root.cmd' '$LOG'"

printf 'echo one\necho two\n' | "$R" >/dev/null 2>&1
eq "stdin：整段落盘" "echo one
echo two" "$(cat "$T/.root.cmd")"

printf 'echo from-file\n' > "$T/script.sh"
"$R" -f "$T/script.sh" >/dev/null 2>&1
eq "-f：拷文件内容" "echo from-file" "$(cat "$T/.root.cmd")"

# --- tvroot 通道 -----------------------------------------------------------
: > "$LOG"
rm -f "$T/poll"
out=$("$R" -t 'echo tv' 2>&1)
eq "-t：去掉 DONE 行后输出 payload" "payload-out" "$out"
no "-t：不走 /factory/su 那条路" "grep -q 'shell /factory/su' '$LOG'"
yes "-t：payload 末尾自己把输出改成可读" \
    "tail -1 '$T/tvroot.cmd' | grep -q 'chmod 644 /data/local/tmp/tvroot.out'"

# --- 没有 /factory/su 时要说清楚 -------------------------------------------
touch "$T/no_su"
out=$("$R" 'id' 2>&1); rc=$?
[ "$rc" -ne 0 ] && pass "无 su：非零退出" || fail "无 su：非零退出" "非零" "$rc"
yes "无 su：提示改用 -t" "printf '%s' \"\$out\" | grep -q tvroot"

summary "t-device-root"
