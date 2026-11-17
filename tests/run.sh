#!/bin/bash
# 跑全部测试。CI 和本地用同一条命令：bash tests/run.sh
#
#   shell 部分：只看各脚本的退出码（每个 t-*.sh 自己打印 ok/FAIL）
#   node 部分：题库结构 check.js、页面端到端 sim.js，检查关键行
set -u

ROOT=$(cd "$(dirname "$0")/.." && pwd)
FAILED=""
COUNT=0

banner() { printf '\n\033[1m-- %s\033[0m\n' "$*"; }

record_fail() {
  FAILED="$FAILED $1"
}

# ---- shell 测试 ------------------------------------------------------------
for f in "$ROOT"/tests/t-*.sh; do
  COUNT=$((COUNT + 1))
  banner "$(basename "$f")"
  if bash "$f"; then
    :
  else
    record_fail "$(basename "$f")"
  fi
done

# ---- 题库与页面 ------------------------------------------------------------
NODE=${NODE:-node}
if ! command -v "$NODE" >/dev/null 2>&1; then
  printf '\n\033[1m-- node 测试\033[0m\n  跳过：找不到 node（设置 NODE=/path/to/node）\n'
else
  COUNT=$((COUNT + 2))

  banner "quiz/check.js  题库结构"
  out=$("$NODE" "$ROOT/quiz/check.js" 2>&1)
  if printf '%s' "$out" | grep -qE 'bad: 0'; then
    printf '%s\n' "$out" | grep -E 'items checked|bad:' | sed 's/^/  /'
    echo "  ok"
  else
    printf '%s\n' "$out" | tail -15
    record_fail "check.js"
  fi

  banner "quiz/sim.js  页面端到端"
  out=$("$NODE" "$ROOT/quiz/sim.js" 2>&1)
  if printf '%s' "$out" | grep -qE 'problems: 0'; then
    printf '%s\n' "$out" | grep -E 'rounds|problems|fresh after reload' | sed 's/^/  /'
    echo "  ok"
  else
    printf '%s\n' "$out" | tail -15
    record_fail "sim.js"
  fi
fi

# ---- 汇总 ------------------------------------------------------------------
printf '\n'
if [ -z "$FAILED" ]; then
  printf '\033[1;32m全部通过\033[0m（%d 组）\n' "$COUNT"
  exit 0
fi
printf '\033[1;31m失败\033[0m：%s\n' "$FAILED"
exit 1
