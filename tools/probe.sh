#!/usr/bin/env bash
# 采样电视当前的前台应用，帮你在新机器上填 SKIP / WATCH。
#
#   tools/probe.sh                    # 看一眼现在是谁在前台（包名 + 组件）
#   tools/probe.sh -t 60              # 采样 60 秒，按停留时长汇总
#   tools/probe.sh -t 60 --emit watch # 输出一行可粘贴的 WATCH=
#   tools/probe.sh -t 60 --emit skip  # 输出一行可粘贴的 SKIP=
#   tools/probe.sh --host 192.168.1.9:5555
#
# 用法建议：跑起来之后拿遥控器把该计时的应用（影视、直播、HDMI）和不该计时的
# 界面（桌面、设置）各停几秒，采样结束就能看出谁是谁。
set -uo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
CONF="${CONF:-$ROOT/config/gate.conf}"
ADB="${ADB:-adb}"
HOST=""
SECS=0
EMIT=""
INTERVAL=1.5

while [ $# -gt 0 ]; do
  case "$1" in
    --host) HOST="$2"; shift 2 ;;
    -t|--time) SECS="$2"; shift 2 ;;
    --emit) EMIT="$2"; shift 2 ;;
    --interval) INTERVAL="$2"; shift 2 ;;
    -h|--help) sed -n '2,13p' "$0"; exit 0 ;;
    *) echo "未知参数: $1" >&2; exit 2 ;;
  esac
done

conf_get() { sed -n "s/^$1=//p" "$CONF" | head -1 | sed 's/[[:space:]]*#.*$//; s/[[:space:]]*$//'; }
[ -n "$HOST" ] || HOST="$(conf_get ADB_HOST)"
A() { "$ADB" -s "$HOST" "$@"; }

"$ADB" connect "$HOST" >/dev/null 2>&1
A shell true >/dev/null 2>&1 || { echo "连不上 $HOST" >&2; exit 1; }

# Same parsing as gate.sh, done on the device in one round trip.
read_comp() {
  A shell '
    l=$(dumpsys window windows 2>/dev/null | grep mCurrentFocus= | head -1)
    [ -z "$l" ] && l=$(dumpsys window 2>/dev/null | grep mCurrentFocus= | head -1)
    case "$l" in "") echo null; exit 0 ;; esac
    echo "$l" | sed "s/.*mCurrentFocus=//; s/}.*//; s/.* //"
  ' 2>/dev/null | tr -d '\r' | head -1
}

if [ "$SECS" -le 0 ]; then
  comp="$(read_comp)"
  echo "前台组件: ${comp:-null}"
  echo "包名    : ${comp%%/*}"
  [ -n "$EMIT" ] && { echo "--emit 需要配合 -t，例如 tools/probe.sh -t 60 --emit watch" >&2; exit 2; }
  exit 0
fi

declare -A NAMES=()
declare -A PKGS=()
order=()
n=$(( SECS * 10 / 15 ))   # 次数上限，按 1.5s 一拍估
[ "$n" -lt 1 ] && n=1

echo "采样 ${SECS}s（每 ${INTERVAL}s 一次，约 ${n} 次）；用遥控器在各个应用之间停几秒…"
end=$(( $(date +%s) + SECS ))
samples=0
while [ "$(date +%s)" -lt "$end" ]; do
  comp="$(read_comp)"
  pkg="${comp%%/*}"
  case "$pkg" in ''|null) ;; *)
    if [ -z "${NAMES[$pkg]+x}" ]; then
      NAMES[$pkg]=0
      PKGS[$pkg]="$comp"
      order+=("$pkg")
    fi
    NAMES[$pkg]=$(( ${NAMES[$pkg]} + 1 ))
    samples=$((samples + 1))
  ;;
  esac
  sleep "$INTERVAL"
done

if [ "$samples" -eq 0 ]; then
  echo "一次都没采到前台应用（屏幕是否休眠？先按一下遥控器）" >&2
  exit 1
fi

TMP="$(mktemp)"
trap 'rm -f "$TMP"' EXIT

# sort by count desc
printf '%s\n' "${order[@]}" | while read -r p; do
  printf '%s\t%s\n' "${NAMES[$p]}" "$p"
done | sort -rn > "$TMP"

# 每次采样约 INTERVAL 秒
dwell() { awk -v c="$1" -v i="$INTERVAL" 'BEGIN{printf "%.0f", c*i}'; }

# 中文表头宽度按字节算会错位，所以把数字放前面、包名放最后，天然对齐。
say_table() {
  echo "按停留时长排序："
  while IFS=$'\t' read -r c p; do
    printf '  %5ss %5s次  %s\n' "$(dwell "$c")" "$c" "$p"
  done < "$TMP"
  echo
  echo "完整组件名（am start -n 用）："
  while IFS=$'\t' read -r c p; do
    echo "  ${PKGS[$p]}"
  done < "$TMP"
}

case "$EMIT" in
  "")
    say_table
    echo
    echo "提示：改完名单再跑 tools/install.sh 生效；只想按名单计数时把 MODE 设成 watch。"
    ;;
  watch|skip)
    list=""
    while IFS=$'\t' read -r c p; do
      # 系统界面永远不该进 WATCH，但确实该进 SKIP
      if [ "$EMIT" = "watch" ]; then
        case "$p" in com.android.systemui|com.android.settings|com.android.tv.settings) continue ;; esac
      fi
      list="$list $p"
    done < "$TMP"
    echo "# 采样 ${SECS}s，${samples} 次命中；粘贴到 config/gate.conf"
    if [ "$EMIT" = "watch" ]; then
      echo "WATCH=$(echo "$list" | sed 's/^ //')"
    else
      echo "SKIP=$(echo "$list" | sed 's/^ //')"
    fi
    ;;
  *) echo "--emit 只认 watch 或 skip" >&2; exit 2 ;;
esac

