#!/bin/sh
# 前台解析、是否计时、答题页是否在前台、回到原应用。
. "$(dirname "$0")/lib.sh"

echo "判定函数"

E=$(new_env)
cat > "$E/config.sh" <<'CFG'
BROWSER=com.tcl.browser
MODE=except
SKIP=com.android.systemui com.spocky.projengmenu com.android.tv.settings
WATCH=com.tcl.vod com.tcl.tv
GRADE=6
N=4
PORT=9090
CFG
load_lib "$E"

# --- 桩 ---------------------------------------------------------------------
STACK=""
FOCUS=""
ACT=""
AMLOG=$E/am.log
: > "$AMLOG"
OLD_ONLY=""          # 非空 = 模拟只认裸 dumpsys window 的新版 ROM

dumpsys() {
  case "$1" in
    window)
      if [ "${2:-}" = "windows" ] && [ -n "$OLD_ONLY" ]; then
        return 0
      fi
      [ -n "$FOCUS" ] && printf '%s\n' "$FOCUS"
      ;;
    activity) [ -n "$ACT" ] && printf '%s\n' "$ACT" ;;
    power) echo "mWakefulness=Awake" ;;
  esac
}
am() {
  case "$1" in
    stack) printf '%s\n' "$STACK" ;;
    start)
      echo "am $*" >> "$AMLOG"
      # AM_START_WORKS 非空 = 模拟"启动后焦点真的过去了"
      [ -n "$AM_START_WORKS" ] && FOCUS="  mCurrentFocus=Window{1 u0 $AM_START_WORKS/.Main}"
      ;;
    *) echo "am $*" >> "$AMLOG" ;;
  esac
}
monkey() { echo "monkey $*" >> "$AMLOG"; }
sleep() { :; }
date() { echo 1794877000; }
AM_START_WORKS=""

# --- 前台组件解析 -----------------------------------------------------------
FOCUS='  mCurrentFocus=Window{86d2a2f u0 com.tcl.vod/com.tcl.vod.MainActivity}'
eq "fg 取包名" "com.tcl.vod" "$(fg)"
eq "fgc 取完整组件" "com.tcl.vod/com.tcl.vod.MainActivity" "$(fgc)"

FOCUS='  mCurrentFocus=null'
eq "焦点为 null 时 fg=null" "null" "$(fg)"

FOCUS=''
eq "读不到焦点时 fg=null" "null" "$(fg)"

# 新版 ROM（Android 12+）没有 dumpsys window windows，回退到 dumpsys window
OLD_ONLY=1
FOCUS='  mCurrentFocus=Window{3d0e5f1 u0 com.example.app/com.example.app.ui.Main}'
eq "裸 dumpsys window 也能解析" "com.example.app" "$(fg)"
OLD_ONLY=""

# --- 是否计入观看时间 -------------------------------------------------------
counted com.tcl.vod            && r=0 || r=1
eq "except：影视计入" 0 "$r"
counted com.spocky.projengmenu && r=0 || r=1
eq "except：桌面不计入" 1 "$r"
counted com.android.systemui   && r=0 || r=1
eq "except：系统界面不计入" 1 "$r"
counted com.unknown.player     && r=0 || r=1
eq "except：陌生应用也计入" 0 "$r"
counted null                   && r=0 || r=1
eq "null 不计入" 1 "$r"
counted ""                     && r=0 || r=1
eq "空包名不计入" 1 "$r"

MODE=watch
counted com.tcl.vod      && r=0 || r=1
eq "watch：名单内计入" 0 "$r"
counted com.tcl.tv       && r=0 || r=1
eq "watch：名单内（第二个）也计入" 0 "$r"
counted com.unknown.player && r=0 || r=1
eq "watch：名单外不计入" 1 "$r"
MODE=except

# --- 答题页是否在前台 -------------------------------------------------------
STACK='  * Stack #1
    taskId=42 visible=true com.tcl.browser/.SiteMapActivity'
quiz_visible && r=0 || r=1
eq "stack 里 browser 可见" 0 "$r"

STACK='  * Stack #1
    taskId=42 visible=false com.tcl.browser/.SiteMapActivity'
quiz_visible && r=0 || r=1
eq "stack 里 browser 不可见" 1 "$r"

# 没有 am stack list（新 ROM）时退回 dumpsys activity
STACK=''
ACT='  mResumedActivity: ActivityRecord{x u0 com.tcl.browser/.Foo t7}'
quiz_visible && r=0 || r=1
eq "回退：ResumedActivity 是浏览器" 0 "$r"

ACT='  mResumedActivity: ActivityRecord{x u0 com.tcl.vod/.Main t8}'
LAST_BROWSER_TS=""
quiz_visible && r=0 || r=1
eq "回退：别家在前台判为不可见" 1 "$r"

LAST_BROWSER_TS=1794876990     # 10 秒前见过浏览器，宽限内
quiz_visible && r=0 || r=1
eq "回退：20 秒宽限内算可见" 0 "$r"
LAST_BROWSER_TS=1794876000     # 好久没见了
quiz_visible && r=0 || r=1
eq "回退：超过宽限算不可见" 1 "$r"

SAVED_BROWSER=$BROWSER
BROWSER=""
quiz_visible && r=0 || r=1
eq "浏览器未配置时不死循环重开" 0 "$r"
BROWSER=$SAVED_BROWSER

# --- 放行后回到原应用 -------------------------------------------------------
: > "$AMLOG"
resume_prev ""
resume_prev "null"
eq "组件为空/null 时不动" 0 "$(wc -l < "$AMLOG" | tr -d ' ')"

resume_prev "com.tcl.browser/com.tcl.browser.SiteMapActivity"
eq "自己就是浏览器时不重开" 0 "$(wc -l < "$AMLOG" | tr -d ' ')"

: > "$AMLOG"
AM_START_WORKS="com.tcl.vod"
FOCUS='  mCurrentFocus=Window{1 u0 com.tcl.browser/.Foo}'
resume_prev "com.tcl.vod/com.tcl.vod.MainActivity"
yes "am start 一次" '[ $(grep -c "^am start" "$AMLOG") -eq 1 ]'
no  "焦点回来了就不再 monkey" 'grep -q "^monkey" "$AMLOG"'

: > "$AMLOG"
AM_START_WORKS=""      # 模拟 am start 没生效
FOCUS='  mCurrentFocus=Window{1 u0 com.tcl.browser/.Foo}'
resume_prev "com.tcl.vod/com.tcl.vod.MainActivity"
yes "am start 失败时退回 monkey" 'grep -q "^monkey -p com.tcl.vod" "$AMLOG"'

# --- 弹题 URL 的参数 --------------------------------------------------------
: > "$AMLOG"
server_up() { return 0; }
DBG=1
open_quiz
url=$(grep "^am start" "$AMLOG" | tail -1)
yes "URL 带年级"   'echo "$url" | grep -q "?g=6"'
yes "URL 带题数"   'echo "$url" | grep -q "n=4"'
yes "URL 带时间戳" 'echo "$url" | grep -q "t=1794877000"'
yes "URL 带 dbg"   'echo "$url" | grep -q "dbg=1"'
yes "URL 用配置端口" 'echo "$url" | grep -q "127.0.0.1:9090"'

: > "$AMLOG"
DBG=0
open_quiz
url=$(grep "^am start" "$AMLOG" | tail -1)
no "DBG=0 时不带 dbg 参数" 'echo "$url" | grep -q "dbg=1"'

summary "判定函数"
