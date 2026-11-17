#!/bin/sh
# 时钟：日期可信性判断，以及启动时"等时钟稳定"。
. "$(dirname "$0")/lib.sh"

echo "时钟"

E=$(new_env)
load_lib "$E"

# --- date_ok：只认 2024..2100，其余（RTC 掉电的 2000、乱码、空）都不可信 ---
for d in 2024-01-01 2026-11-17 2100-12-31; do
  yes "date_ok $d" "date_ok $d"
done
for d in 2000-01-01 2023-12-31 2101-01-01 "" abc 2026-13; do
  no "date_ok '$d' 不可信" "date_ok '$d'"
done

# --- wait_clock：用序列喂假的 date，sleep 打桩成空 -------------------------
# date 是在 $(...) 子 shell 里被调用的，所以计数必须落在文件上，
# 否则父 shell 看不到"已经被调用了几次"。
TMP=$(mktemp -d)
EFILE=$TMP/epochs
DFILE=$TMP/dates
CNT_S=$TMP/cnt_s
CNT_D=$TMP/cnt_d

date() {
  case "${1:-}" in
    +%s)
      n=$(cat "$CNT_S" 2>/dev/null || echo 0); n=$((n + 1)); echo "$n" > "$CNT_S"
      v=$(sed -n "${n}p" "$EFILE" 2>/dev/null)
      echo "${v:-999999}"
      ;;
    +%Y-%m-%d)
      n=$(cat "$CNT_D" 2>/dev/null || echo 0); n=$((n + 1)); echo "$n" > "$CNT_D"
      v=$(sed -n "${n}p" "$DFILE" 2>/dev/null)
      echo "${v:-2000-01-01}"
      ;;
    *)
      # 日志里的时间戳：不能用掉序列，否则会把测试数据吃光
      echo "11-17 08:00:00"
      ;;
  esac
}
sleep() { :; }

reset() { rm -f "$CNT_S" "$CNT_D"; }
reads_s() { cat "$CNT_S" 2>/dev/null || echo 0; }
reads_d() { cat "$CNT_D" 2>/dev/null || echo 0; }

# 场景 1：时钟一开始就正常（每拍 +3 秒，日期可信）→ 连续 3 次后返回
reset
seq 1000 3 1300 > "$EFILE"
awk 'BEGIN { for (i = 0; i < 20; i++) print "2026-11-17" }' > "$DFILE"
yes "时钟正常：确认 3 次后返回" "wait_clock"
eq "  读了 6 次 epoch（3 轮 × 2）" 6 "$(reads_s)"
eq "  读了 3 次日期" 3 "$(reads_d)"

# 场景 2：先读到 2000 年，然后被 NTP 拨到 2026（今天日志里的情形）
reset
{ printf '1000\n173000\n'; seq 173003 3 173400; } > "$EFILE"
{ printf '2000-01-01\n2000-01-01\n2000-01-01\n'; awk 'BEGIN { for (i = 0; i < 40; i++) print "2026-11-17" }'; } > "$DFILE"
yes "时间被拨动：等到稳定后返回" "wait_clock"
yes "  跳变那一拍没有被算作稳定（多读了几轮）" "[ $(reads_s) -gt 6 ]"

# 场景 3：一直读不到可信时间（没网、RTC 坏）→ 超时返回，不能卡死
reset
seq 1000 3 1400 > "$EFILE"
awk 'BEGIN { for (i = 0; i < 40; i++) print "2000-01-01" }' > "$DFILE"
no "始终不可信：超时后放弃等待" "wait_clock"
yes "  打了未稳定的日志" 'grep -q "clock not settled" "$E/gate.log"'
eq "  最多 30 轮（60 次 epoch 读取）" 60 "$(reads_s)"

# 场景 4：时钟在倒退（回拨）也不能算稳定
reset
{ printf '5000\n'; seq 1000 3 1200; } > "$EFILE"
awk 'BEGIN { for (i = 0; i < 40; i++) print "2026-11-17" }' > "$DFILE"
yes "回拨后仍能等到稳定" "wait_clock"
yes "  回拨那一拍被跳过" "[ $(reads_s) -ge 6 ]"

rm -rf "$TMP"
summary "时钟"
