#!/bin/sh
# 当天次数的读写与跨日清零。
. "$(dirname "$0")/lib.sh"

echo "状态与跨日"

E=$(new_env)

# 覆盖 date，让"今天是哪天"可控（函数优先于外部命令）
FAKE_DAY=2026-11-17
FAKE_EPOCH=1794877000
date() {
  case "${1:-}" in
    +%s) echo "$FAKE_EPOCH" ;;
    *)   echo "$FAKE_DAY" ;;
  esac
}

load_lib "$E"

# --- 没有 state 文件：从 0 开始，并且建出文件 -------------------------------
printf '%s' "$(load_count)" > /tmp/.c
eq "无 state 时 count=0" 0 "$(cat /tmp/.c)"
yes "无 state 时建出文件" '[ -f "$E/state" ]'
eq "新建 state 的日期是今天" "d=2026-11-17" "$(sed -n 1p "$E/state")"

# --- 同一天：原样返回 -------------------------------------------------------
save_state 2026-11-17 4
eq "同一天返回 4" 4 "$(load_count)"
eq "save_state 记录了写入时刻" "t=1794877000" "$(sed -n 3p "$E/state")"

# --- 隔天：清零并写新日期 ---------------------------------------------------
FAKE_DAY=2026-11-18
eq "隔天清零" 0 "$(load_count)"
eq "隔天后 state 日期更新" "d=2026-11-18" "$(sed -n 1p "$E/state")"
yes "隔天有日志" 'grep -q "new day 2026-11-18" "$E/gate.log"'

# --- 隔多天（关机几天再开）：同样清零 ---------------------------------------
save_state 2026-11-17 7
FAKE_DAY=2026-11-21
eq "隔多天清零" 0 "$(load_count)"

# --- state 里的日期不可信（RTC 没对时）：保留次数，不能清 -------------------
save_state 2000-01-01 7
FAKE_DAY=2026-11-17
eq "日期不可信时保留次数" 7 "$(load_count)"
eq "不可信日期会被改成今天" "d=2026-11-17" "$(sed -n 1p "$E/state")"

# --- 计数被写坏：当 0 处理，不能让脚本崩 -------------------------------------
printf 'd=2026-11-17\nn=abc\n' > "$E/state"
eq "非数字 n 当 0" 0 "$(load_count)"
printf 'd=2026-11-17\nn=\n' > "$E/state"
eq "空 n 当 0" 0 "$(load_count)"
printf 'n=5\n' > "$E/state"
eq "缺日期时按不可信处理并保留 5" 5 "$(load_count)"

# --- 文件权限：看门狗以 root 写，shell 用户要能读 ---------------------------
save_state 2026-11-17 2
eq "state 权限 644" 644 "$(stat -c %a "$E/state")"

summary "状态与跨日"
