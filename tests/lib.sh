# 测试共用：断言、打桩、临时设备目录。
# 用法：. "$(dirname "$0")/lib.sh"，然后 eq / yes / no，最后 summary。
set -u

ROOT=${ROOT:-$(cd "$(dirname "$0")/.." && pwd)}
PASS=0
FAIL=0

pass() { PASS=$((PASS + 1)); printf '    ok   %s\n' "$1"; }
fail() {
  FAIL=$((FAIL + 1))
  printf '    FAIL %s\n         期望: %s\n         实际: %s\n' "$1" "$2" "$3"
}

# eq <说明> <期望> <实际>
eq() {
  if [ "$2" = "$3" ]; then pass "$1"; else fail "$1" "$2" "$3"; fi
}

# yes/no <说明> <要 eval 的表达式>
yes() { if eval "$2"; then pass "$1"; else fail "$1" "成立" "不成立"; fi; }
no()  { if eval "$2"; then fail "$1" "不成立" "成立"; else pass "$1"; fi; }

summary() {
  printf '\n%s: %d passed, %d failed\n' "$1" "$PASS" "$FAIL"
  [ "$FAIL" -eq 0 ]
}

# 临时"设备目录"：函数库只往这里写 gate.log / state
new_env() {
  D=$(mktemp -d)
  mkdir -p "$D/cgi-bin"
  : > "$D/config.sh"
  printf '%s' "$D"
}

# 加载函数库。W 指向临时目录，这样 log/state 不会碰到真实路径。
load_lib() {
  W=$1
  export W
  . "$ROOT/gate/lib.sh"
}
