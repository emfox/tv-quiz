#!/bin/sh
# 语法检查：改脚本最容易犯的错（少个 fi、引号不配对）先在这里挡住。
. "$(dirname "$0")/lib.sh"

echo "语法"

for f in gate/gate.sh gate/lib.sh gate/boot.sh.in gate/cgi-bin/pass.sh.in gate/cgi-bin/log.sh.in \
         device/su-link.sh device/launcher/lchome.sh; do
  if sh -n "$ROOT/$f" 2>/dev/null; then
    pass "sh -n $f"
  else
    fail "sh -n $f" "语法正确" "$(sh -n "$ROOT/$f" 2>&1)"
  fi
done

for f in tools/install.sh tools/status.sh tools/probe.sh tools/uninstall.sh tools/tvroot.sh \
         device/root.sh device/launcher/install.sh \
         tests/run.sh tests/t-install.sh tests/fake-adb.sh tests/t-device-root.sh; do
  if bash -n "$ROOT/$f" 2>/dev/null; then
    pass "bash -n $f"
  else
    fail "bash -n $f" "语法正确" "$(bash -n "$ROOT/$f" 2>&1)"
  fi
done

# gate.sh 必须能加载函数库（拆文件后最容易漏的就是这一句）
yes "gate.sh 引用了 lib.sh" 'grep -q "^\. .*lib\.sh" "$ROOT/gate/gate.sh"'
yes "install.sh 会部署 lib.sh" 'grep -q "lib.new" "$ROOT/tools/install.sh"'

summary "语法"
