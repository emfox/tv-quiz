#!/bin/sh
# 配置解析：默认值、行内注释、档位表。
. "$(dirname "$0")/lib.sh"

echo "配置解析"

# --- 空配置：全部走默认值 ---------------------------------------------------
E=$(new_env)
load_lib "$E"
eq "空配置 GRADE=5"       5    "$GRADE"
eq "空配置 N=3"           3    "$N"
eq "空配置 STEP=10"       10   "$STEP"
eq "空配置 QUIZ_TIMEOUT"  420  "$QUIZ_TIMEOUT"
eq "空配置 MAX_TIMEOUTS"  3    "$MAX_TIMEOUTS"
eq "空配置 TIMEOUT_ACTION" sleep "$TIMEOUT_ACTION"
eq "空配置 PORT"          8088 "$PORT"
eq "空配置 MODE"          except "$MODE"
eq "空配置 LIMITS 回落到 LIMIT" 600 "$LIMITS"

# --- 正常取值 ---------------------------------------------------------------
E=$(new_env)
cat > "$E/config.sh" <<'CFG'
LIMITS=600 600 480 480 300
GRADE=6
N=4
MODE=watch
AWAY_RESET=900
PORT=9090
DBG=1
CFG
load_lib "$E"
eq "LIMITS"        "600 600 480 480 300" "$LIMITS"
eq "GRADE"         6    "$GRADE"
eq "N"             4    "$N"
eq "MODE"          watch "$MODE"
eq "AWAY_RESET"    900  "$AWAY_RESET"
eq "PORT"          9090 "$PORT"
eq "DBG"           1    "$DBG"

# --- 行内注释要被剥掉（写错注释会变成值的一部分，这是常见事故）-------------
E=$(new_env)
cat > "$E/config.sh" <<'CFG'
LIMITS=300 300   # 两次 5 分钟
GRADE=6          # 六年级
TIMEOUT_ACTION=none   # 不关屏
CFG
load_lib "$E"
eq "注释不进入 LIMITS"  "300 300" "$LIMITS"
eq "注释不进入 GRADE"   6    "$GRADE"
eq "注释不进入 ACTION"  none "$TIMEOUT_ACTION"

# --- 显式空值：LIMITS 回落到 LIMIT -----------------------------------------
E=$(new_env)
printf 'LIMIT=300\nLIMITS=\n' > "$E/config.sh"
load_lib "$E"
eq "LIMITS 为空时用 LIMIT" "300" "$LIMITS"

# --- 档位表：第 k 次用第 k 档，超出后重复最后一档 ---------------------------
E=$(new_env)
printf 'LIMITS=600 600 480 480 300\n' > "$E/config.sh"
load_lib "$E"
eq "第 1 档"  600 "$(limit_for 1)"
eq "第 2 档"  600 "$(limit_for 2)"
eq "第 3 档"  480 "$(limit_for 3)"
eq "第 4 档"  480 "$(limit_for 4)"
eq "第 5 档"  300 "$(limit_for 5)"
eq "第 9 档沿用最后一档" 300 "$(limit_for 9)"
eq "第 0 档也取第一档"   600 "$(limit_for 0)"

# --- 名单：lib 里用前后空格包裹，便于 *" $p "* 匹配 -------------------------
E=$(new_env)
printf 'WATCH=com.a com.b\nSKIP=com.x\n' > "$E/config.sh"
load_lib "$E"
eq "WATCH 前后加空格" " com.a com.b " "$WATCH"
eq "SKIP 前后加空格"  " com.x "       "$SKIP"

summary "配置解析"
