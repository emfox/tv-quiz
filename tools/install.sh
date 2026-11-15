#!/usr/bin/env bash
# 把 quiz/ 和 gate/ 部署到电视，按需安装 init 自启服务并重启看门狗。
#
#   tools/install.sh                       # 用 config/gate.conf 里的地址
#   tools/install.sh --host 192.168.1.9:5555
#   tools/install.sh --conf other.conf
#   tools/install.sh --no-restart          # 只推文件，不动正在跑的服务
#
# 只推文件不需要 root；安装 /vendor/etc/init/tvgate.rc 和重启服务需要 root
# （本机 TCL 的 root 走 init 服务 tvroot，见 tools/tvroot.sh）。
set -uo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
CONF="${CONF:-$ROOT/config/gate.conf}"
ADB="${ADB:-adb}"
HOST=""
RESTART=1

while [ $# -gt 0 ]; do
  case "$1" in
    --host) HOST="$2"; shift 2 ;;
    --conf) CONF="$2"; shift 2 ;;
    --no-restart) RESTART=0; shift ;;
    -h|--help) sed -n '2,12p' "$0"; exit 0 ;;
    *) echo "未知参数: $1" >&2; exit 2 ;;
  esac
done

[ -f "$CONF" ] || { echo "找不到配置: $CONF" >&2; exit 2; }
conf_get() { sed -n "s/^$1=//p" "$CONF" | head -1 | sed 's/[[:space:]]*#.*$//; s/[[:space:]]*$//'; }

[ -n "$HOST" ] || HOST="$(conf_get ADB_HOST)"
D="$(conf_get DEVICE_DIR)"
D="${D:-/data/local/tmp/tvquiz}"

say() { printf '\033[1m== %s\033[0m\n' "$*"; }
A() { "$ADB" -s "$HOST" "$@"; }

say "连接 $HOST"
"$ADB" connect "$HOST" >/dev/null 2>&1
if ! A shell true >/dev/null 2>&1; then
  echo "连不上 $HOST：检查电视是否开机、网络是否同网段、adb 调试是否打开" >&2
  exit 1
fi
MODEL="$(A shell getprop ro.product.model 2>/dev/null | tr -d '\r')"
echo "设备型号: ${MODEL:-未知}"

say "推送文件到 $D"
A shell "mkdir -p $D/cgi-bin" || exit 1
for f in index.html gen.js pick.js bank.json; do
  A push "$ROOT/quiz/$f" "$D/$f" >/dev/null || { echo "推送 $f 失败" >&2; exit 1; }
done
A push "$ROOT/gate/cgi-bin/pass.sh" "$D/cgi-bin/pass.sh" >/dev/null || exit 1
A push "$ROOT/gate/gate.sh" "$D/gate.new" >/dev/null || exit 1
A push "$CONF" "$D/config.sh" >/dev/null || exit 1
A shell "cd $D && mv -f gate.new gate.sh && chmod 755 gate.sh cgi-bin/pass.sh" || exit 1
echo "文件就位: $(A shell "ls $D" | tr '\n' ' ')"

# ---- root 通道 ------------------------------------------------------------
RC_TARGET=/vendor/etc/init/tvgate.rc
root_mode=""
if [ "$(A shell getprop init.svc.tvroot 2>/dev/null | tr -d '\r')" = "running" ] && [ -x "$ROOT/tools/tvroot.sh" ]; then
  root_mode="tvroot"
elif A shell "su -c true" >/dev/null 2>&1; then
  root_mode="su"
fi
root_run() {
  case "$root_mode" in
    tvroot) TV_HOST="$HOST" "$ROOT/tools/tvroot.sh" "$1" ;;
    su) A shell "su -c '$1'" ;;
    *) return 3 ;;
  esac
}

# ---- init 自启服务 --------------------------------------------------------
if [ "$(A shell "ls $RC_TARGET 2>/dev/null | wc -l" | tr -d '\r')" = "0" ]; then
  say "安装 init 服务 $RC_TARGET"
  if [ -n "$root_mode" ]; then
    # 用模板渲染出设备路径，再推给 root 拷进 /vendor
    sed "s|@DEVICE_DIR@|$D|g" "$ROOT/gate/tvgate.rc.in" > "$ROOT/.tvgate.rc"
    A push "$ROOT/.tvgate.rc" "/data/local/tmp/tvgate.rc" >/dev/null
    rm -f "$ROOT/.tvgate.rc"
    root_run "cp /data/local/tmp/tvgate.rc $RC_TARGET && chmod 644 $RC_TARGET && sync"
    echo "已安装（重启电视后由 init 拉起）"
  else
    echo "无 root：跳过。需要手动把 gate/tvgate.rc.in（替换 @DEVICE_DIR@ 后）放到 $RC_TARGET" >&2
  fi
else
  echo "init 服务已存在: $RC_TARGET"
fi

# ---- 重启看门狗 ----------------------------------------------------------
if [ "$RESTART" = "1" ] && [ -n "$root_mode" ]; then
  say "重启看门狗（配置与脚本生效）"
  root_run "for p in /proc/[0-9]*; do c=\$(cat \$p/cmdline 2>/dev/null | tr '\\000' ' '); case \"\$c\" in *$D/gate.sh*) kill \${p#/proc/};; esac; done"
  sleep 3
  echo "服务状态: $(A shell getprop init.svc.tvgate | tr -d '\r')"
elif [ "$RESTART" = "1" ]; then
  echo "无 root：新配置要等下次重启电视才生效" >&2
fi

say "完成"
"$ROOT/tools/status.sh" --host "$HOST" || true
