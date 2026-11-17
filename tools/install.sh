#!/usr/bin/env bash
# 把 quiz/ 和 gate/ 部署到电视，按需安装开机自启并重启看门狗。
#
#   tools/install.sh                        # 用 config/gate.conf 里的地址与 PROFILE
#   tools/install.sh --host 192.168.1.9:5555
#   tools/install.sh --profile generic      # 换一份设备画像（config/profiles/）
#   tools/install.sh --conf other.conf
#   tools/install.sh --no-restart           # 只推文件，不动正在跑的服务
#   tools/install.sh --list-profiles
#
# 只推文件不需要 root；装自启（/vendor/etc/init、/data/adb/service.d、init.d）
# 和重启看门狗需要 root，依次尝试 tvroot 服务（本机 TCL）与 su。
set -uo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
CONF="${CONF:-$ROOT/config/gate.conf}"
ADB="${ADB:-adb}"
HOST=""
RESTART=1
PROFILE_ARG=""

while [ $# -gt 0 ]; do
  case "$1" in
    --host) HOST="$2"; shift 2 ;;
    --conf) CONF="$2"; shift 2 ;;
    --profile) PROFILE_ARG="$2"; shift 2 ;;
    --no-restart) RESTART=0; shift ;;
    --list-profiles)
      for f in "$ROOT"/config/profiles/*.conf; do
        b="$(basename "$f" .conf)"
        printf '%-10s %s\n' "$b" "$(sed -n 's/^#[[:space:]]*//p' "$f" | head -1)"
      done
      exit 0 ;;
    -h|--help) sed -n '2,14p' "$0"; exit 0 ;;
    *) echo "未知参数: $1" >&2; exit 2 ;;
  esac
done

[ -f "$CONF" ] || { echo "找不到配置: $CONF" >&2; exit 2; }
conf_get() { sed -n "s/^$1=//p" "$CONF" | head -1 | sed 's/[[:space:]]*#.*$//; s/[[:space:]]*$//'; }

say() { printf '\033[1m== %s\033[0m\n' "$*"; }

# ---- profile 与配置合并 ---------------------------------------------------
PROFILE="${PROFILE_ARG:-$(conf_get PROFILE)}"
PROFILE="${PROFILE:-generic}"
PROFILE_FILE="$ROOT/config/profiles/$PROFILE.conf"
[ -f "$PROFILE_FILE" ] || { echo "找不到设备画像: $PROFILE_FILE（用 --list-profiles 看有哪些）" >&2; exit 2; }

MERGED="$(mktemp)"
trap 'rm -f "$MERGED" "$MERGED".tmp "$MERGED".rc "$MERGED".boot "$MERGED".cgi' EXIT
# profile 在前、gate.conf 在后：同名参数以 gate.conf 为准。最后按 key 去重，
# 这样设备端的 cfg()（取第一行）与这里的判断不会读到不同的值。
{ grep -vE '^[[:space:]]*(#|$)' "$PROFILE_FILE"; echo; grep -vE '^[[:space:]]*(#|$)' "$CONF"; } \
  | grep -vE '^(ADB_HOST|DEVICE_DIR|PROFILE)=' \
  | tac | awk -F= '!($1 in s){s[$1]=1; print}' | tac > "$MERGED"

merged_get() { sed -n "s/^$1=//p" "$MERGED" | head -1 | sed 's/[[:space:]]*$//'; }
set_kv() { # file key value -> exactly one occurrence of key
  { grep -v "^$2=" "$1" || true; } > "$1.tmp"
  echo "$2=$3" >> "$1.tmp"
  mv "$1.tmp" "$1"
}

[ -n "$HOST" ] || HOST="$(conf_get ADB_HOST)"
D="$(conf_get DEVICE_DIR)"; D="${D:-/data/local/tmp/tvquiz}"
A() { "$ADB" -s "$HOST" "$@"; }

say "连接 $HOST"
"$ADB" connect "$HOST" >/dev/null 2>&1
if ! A shell true >/dev/null 2>&1; then
  echo "连不上 $HOST：检查电视是否开机、网络是否同网段、adb 调试是否打开" >&2
  exit 1
fi
MODEL="$(A shell getprop ro.product.model 2>/dev/null | tr -d '\r')"
ANDROID="$(A shell getprop ro.build.version.release 2>/dev/null | tr -d '\r')"
echo "设备: ${MODEL:-未知} / Android ${ANDROID:-?}  画像: $PROFILE"
PKGS="$(A shell pm list packages 2>/dev/null | tr -d '\r')"
has_pkg() { printf '%s\n' "$PKGS" | grep -qx "package:$1"; }
dev_exists() { A shell "[ -e $1 ] && echo y" 2>/dev/null | tr -d '\r' | grep -q y; }

# ---- root 通道 ------------------------------------------------------------
root_mode=""
if [ "$(A shell getprop init.svc.tvroot 2>/dev/null | tr -d '\r')" = "running" ] && [ -x "$ROOT/tools/tvroot.sh" ]; then
  root_mode="tvroot"
elif A shell "su -c true" >/dev/null 2>&1; then
  root_mode="su"
fi
want_root="$(merged_get ROOT_MODE)"
case "$want_root" in su|tvroot)
  if [ "$want_root" != "$root_mode" ] && [ "$want_root" = "su" ] && A shell "su -c true" >/dev/null 2>&1; then
    root_mode="su"
  fi ;;
esac
root_run() {
  case "$root_mode" in
    tvroot) TV_HOST="$HOST" "$ROOT/tools/tvroot.sh" "$1" ;;
    su) A shell "su -c '$1'" ;;
    *) return 3 ;;
  esac
}

# ---- 设备参数解析：浏览器 / 自启方式 --------------------------------------
BROWSER="$(merged_get BROWSER)"
case "$BROWSER" in
  ""|auto)
    BROWSER=""
    for b in com.tcl.browser com.android.chrome com.android.browser com.microsoft.emmx \
             org.mozilla.tv.firefox com.brave.browser com.opera.browser; do
      has_pkg "$b" && { BROWSER="$b"; break; }
    done
    if [ -z "$BROWSER" ]; then
      echo "警告: 没找到可用的浏览器，答题页打不开。装一个能访问 http:// 的浏览器后" >&2
      echo "      把 BROWSER=<包名> 写进 config/gate.conf（htmlviewer 不行：没有 INTERNET 权限）" >&2
    fi ;;
esac
set_kv "$MERGED" BROWSER "$BROWSER"

BOOT_MODE="$(merged_get BOOT_MODE)"
case "$BOOT_MODE" in
  ""|auto)
    if dev_exists /data/adb/service.d; then
      BOOT_MODE=magisk
    elif [ -n "$root_mode" ] && dev_exists /vendor/etc/init; then
      BOOT_MODE=initrc
    elif dev_exists /system/etc/init.d; then
      BOOT_MODE=initd
    else
      BOOT_MODE=none
    fi ;;
esac
set_kv "$MERGED" BOOT_MODE "$BOOT_MODE"
BB="$(merged_get BB)"; BB="${BB:-auto}"
echo "浏览器: ${BROWSER:-未找到}  busybox: $BB  自启: $BOOT_MODE  root: ${root_mode:-无}"

# ---- 推文件 ---------------------------------------------------------------
say "推送文件到 $D"
A shell "mkdir -p $D/cgi-bin" || exit 1
for f in index.html gen.js pick.js bank.json; do
  A push "$ROOT/quiz/$f" "$D/$f" >/dev/null || { echo "推送 $f 失败" >&2; exit 1; }
done
for f in pass log; do
  sed "s|@DEVICE_DIR@|$D|g" "$ROOT/gate/cgi-bin/$f.sh.in" > "$MERGED.cgi"
  A push "$MERGED.cgi" "$D/cgi-bin/$f.sh" >/dev/null || { echo "推送 cgi-bin/$f.sh 失败" >&2; exit 1; }
done
A push "$ROOT/gate/gate.sh" "$D/gate.new" >/dev/null || exit 1
A push "$ROOT/gate/lib.sh" "$D/lib.new" >/dev/null || exit 1
A push "$MERGED" "$D/config.sh" >/dev/null || exit 1
A shell "cd $D && mv -f lib.new lib.sh && mv -f gate.new gate.sh && chmod 644 lib.sh && chmod 755 gate.sh cgi-bin/pass.sh cgi-bin/log.sh" || exit 1
echo "文件就位: $(A shell "ls $D" | tr '\n' ' ')"

# ---- 开机自启 -------------------------------------------------------------
RC_TARGET=/vendor/etc/init/tvgate.rc
BOOT_MAGISK=/data/adb/service.d/50-tvquiz.sh
BOOT_INITD=/system/etc/init.d/99-tvquiz

install_boot() {
  case "$BOOT_MODE" in
    initrc)
      if [ "$(A shell "ls $RC_TARGET 2>/dev/null | wc -l" | tr -d '\r')" != "0" ]; then
        echo "init 服务已存在: $RC_TARGET（不覆盖，改了目录请手动删）"
        return 0
      fi
      if [ -z "$root_mode" ]; then
        echo "无 root：需要手动把 gate/tvgate.rc.in（替换 @DEVICE_DIR@ 后）放到 $RC_TARGET" >&2
        return 0
      fi
      sed "s|@DEVICE_DIR@|$D|g" "$ROOT/gate/tvgate.rc.in" > "$MERGED.rc"
      A push "$MERGED.rc" "/data/local/tmp/tvgate.rc" >/dev/null
      # /vendor is mounted read-only on boot; remount first or cp silently fails
      root_run "mount -o remount,rw /vendor 2>/dev/null; mount -o remount,rw / 2>/dev/null; cp /data/local/tmp/tvgate.rc $RC_TARGET && chmod 644 $RC_TARGET && sync" >/dev/null
      if [ "$(A shell "ls $RC_TARGET 2>/dev/null | wc -l" | tr -d '\r')" = "1" ]; then
        echo "已装 $RC_TARGET（重启电视后由 init 拉起）"
      else
        echo "!! 写入 $RC_TARGET 失败（/vendor 只读且 remount 不了）" >&2
      fi
      ;;
    magisk|initd)
      if [ -z "$root_mode" ]; then
        echo "无 root：需要手动把 gate/boot.sh.in（替换 @DEVICE_DIR@ 后）放到 $([ "$BOOT_MODE" = magisk ] && echo "$BOOT_MAGISK" || echo "$BOOT_INITD")" >&2
        return 0
      fi
      TGT="$BOOT_MAGISK"; [ "$BOOT_MODE" = initd ] && TGT="$BOOT_INITD"
      sed "s|@DEVICE_DIR@|$D|g" "$ROOT/gate/boot.sh.in" > "$MERGED.boot"
      A push "$MERGED.boot" "/data/local/tmp/tvquiz-boot.sh" >/dev/null
      if [ "$BOOT_MODE" = initd ]; then
        root_run "mount -o remount,rw / 2>/dev/null; mkdir -p $(dirname "$TGT") && cp /data/local/tmp/tvquiz-boot.sh $TGT && chmod 755 $TGT && sync" \
          || echo "装 init.d 失败（/system 只读且 remount 被拒）" >&2
      else
        root_run "mkdir -p $(dirname "$TGT") && cp /data/local/tmp/tvquiz-boot.sh $TGT && chmod 755 $TGT && sync" \
          || echo "装 service.d 失败" >&2
      fi
      echo "已装 $TGT（重启电视后自动拉起）"
      ;;
    none)
      echo "自启: none —— 这台机器没找到可用的自启位置，重启后需要手动跑 $D/gate.sh" >&2 ;;
    *) echo "未知 BOOT_MODE=$BOOT_MODE，跳过自启" >&2 ;;
  esac
}
say "开机自启（$BOOT_MODE）"
install_boot

# ---- 重启看门狗 ----------------------------------------------------------
if [ "$RESTART" = "1" ] && [ -n "$root_mode" ]; then
  say "重启看门狗（配置与脚本生效）"
  root_run "for p in /proc/[0-9]*; do c=\$(cat \$p/cmdline 2>/dev/null | tr '\\000' ' '); case \"\$c\" in *$D/gate.sh*) kill \${p#/proc/};; esac; done"
  sleep 3
  svc="$(A shell getprop init.svc.tvgate 2>/dev/null | tr -d '\r')"
  if [ "$BOOT_MODE" = "initrc" ]; then
    echo "服务状态: ${svc:-?}"
  else
    # 非 initrc 时没有 init 服务托管，直接确认进程在跑
    running="$(A shell "for p in /proc/[0-9]*; do c=\$(cat \$p/cmdline 2>/dev/null | tr '\\0' ' '); case \"\$c\" in *$D/gate.sh*) echo yes;; esac; done" | tr -d '\r' | head -1)"
    echo "进程: ${running:-没起来}"
  fi
elif [ "$RESTART" = "1" ]; then
  echo "无 root：新配置要等下次重启电视才生效" >&2
fi

say "完成"
"$ROOT/tools/status.sh" --host "$HOST" || true
