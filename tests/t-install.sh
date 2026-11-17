#!/bin/bash
# 安装脚本：配置合并、浏览器探测、自启落点。全部跑在假 adb 上，不碰真机。
. "$(dirname "$0")/lib.sh"

echo "安装脚本"

ADB_STUB=$ROOT/tests/fake-adb.sh
chmod +x "$ADB_STUB" 2>/dev/null

setup() {
  S=$(mktemp -d)
  P=$(mktemp -d)
  cat > "$S/packages" <<'PKGS'
package:com.tcl.browser
package:com.tcl.vod
package:com.android.tv.settings
PKGS
  : > "$S/log"
}

run_install() {
  FAKE_STATE="$S" FAKE_PUSHED="$P" FAKE_LOG="$S/log" ADB="$ADB_STUB" \
    bash "$ROOT/tools/install.sh" --host 10.0.0.9:5555 "$@" 2>&1
}

merged_keys() { cut -d= -f1 "$P/config.sh" | grep -c . ; }
dup_keys() { cut -d= -f1 "$P/config.sh" | sort | uniq -d | tr '\n' ' '; }

# --- 画像列表与错误处理 -----------------------------------------------------
out=$(bash "$ROOT/tools/install.sh" --list-profiles 2>&1)
yes "list-profiles 列出 tcl"     'echo "$out" | grep -q "^tcl"'
yes "list-profiles 列出 generic" 'echo "$out" | grep -q "^generic"'

bash "$ROOT/tools/install.sh" --profile nosuch --host 10.0.0.9:5555 >/dev/null 2>&1
eq "画像不存在时退出码 2" 2 "$?"

# --- 场景 1：tcl 画像，/vendor/etc/init 可写，有 root -----------------------
setup
touch "$S/vendor_init"
out=$(run_install --no-restart)
yes "tcl：选中 initrc"          'echo "$out" | grep -q "自启: initrc"'
yes "tcl：装了 init 服务"        'echo "$out" | grep -q "已装 /vendor/etc/init/tvgate.rc"'
yes "tcl：浏览器沿用画像"        'echo "$out" | grep -q "浏览器: com.tcl.browser"'
yes "tcl：推上来的 config.sh 带 BROWSER" 'grep -qx "BROWSER=com.tcl.browser" "$P/config.sh"'
eq  "tcl：config.sh 没有重复 key" "" "$(dup_keys)"
yes "tcl：渲染过的 rc 指向安装目录" 'grep -q "@DEVICE_DIR@" "$P/tvgate.rc" && fail=1 || true; grep -q "/data/local/tmp/tvquiz/gate.sh" "$P/tvgate.rc"'

# 已经装过 rc 时不覆盖
touch "$S/rc_exists"
out=$(run_install --no-restart)
yes "rc 已存在时不覆盖" 'echo "$out" | grep -q "init 服务已存在"'

# --- 场景 2：generic 画像 + Magisk 的 service.d ------------------------------
setup
touch "$S/service_d"
out=$(run_install --profile generic --no-restart)
yes "generic：探测到 magisk"    'echo "$out" | grep -q "自启: magisk"'
yes "generic：装了 service.d"   'echo "$out" | grep -q "已装 /data/adb/service.d/50-tvquiz.sh"'
yes "generic：浏览器自动探测"    'echo "$out" | grep -q "浏览器: com.tcl.browser"'

# --- 场景 3：只有 init.d ----------------------------------------------------
setup
touch "$S/init_d"
out=$(run_install --profile generic --no-restart)
yes "只有 init.d 时选 initd"     'echo "$out" | grep -q "自启: initd"'
yes "initd：装了 99-tvquiz"      'echo "$out" | grep -q "已装 /system/etc/init.d/99-tvquiz"'

# --- 场景 4：三个位置都没有 ------------------------------------------------
setup
out=$(run_install --profile generic --no-restart)
yes "都没有时 BOOT_MODE=none"    'echo "$out" | grep -q "自启: none"'
yes "none 时提示手动启动"        'echo "$out" | grep -q "重启后需要手动跑"'

# --- 场景 5：没有 root ------------------------------------------------------
setup
touch "$S/vendor_init" "$S/no_root"
out=$(run_install --no-restart)
yes "无 root 时仍推文件"         'grep -qx "BROWSER=com.tcl.browser" "$P/config.sh"'
yes "无 root 时提示手动放 rc"    'echo "$out" | grep -q "无 root：需要手动把"'

# --- 合并规则：gate.conf 覆盖 profile --------------------------------------
setup
touch "$S/vendor_init"
cat > "$S/conf" <<'CFG'
ADB_HOST=10.0.0.9:5555
DEVICE_DIR=/data/local/tmp/tvquiz
PROFILE=generic
BROWSER=com.example.mine
GRADE=6
LIMITS=100 100
CFG
out=$(run_install --conf "$S/conf" --no-restart)
yes "gate.conf 覆盖 profile 的 BROWSER" 'grep -qx "BROWSER=com.example.mine" "$P/config.sh"'
yes "gate.conf 的 GRADE 生效"          'grep -qx "GRADE=6" "$P/config.sh"'
yes "gate.conf 的 LIMITS 生效"         'grep -qx "LIMITS=100 100" "$P/config.sh"'
eq  "覆盖后仍无重复 key" "" "$(dup_keys)"
no  "ADB_HOST 不会被写进设备配置"      'grep -q "^ADB_HOST=" "$P/config.sh"'
no  "PROFILE 不会被写进设备配置"       'grep -q "^PROFILE=" "$P/config.sh"'

summary "安装脚本"
