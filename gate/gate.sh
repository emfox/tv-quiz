#!/system/bin/sh
# Viewing gate: after LIMITS[k] seconds of screen time, require a quiz.
#
# Everything device specific (browser package, busybox path, autostart style)
# comes from config.sh, which tools/install.sh renders from
# config/profiles/<name>.conf + config/gate.conf. Nothing below should need
# editing to move to another Android TV.

W=/data/local/tmp/tvquiz
LOG=$W/gate.log

cfg() {
  sed -n "s/^$1=//p" "$W/config.sh" 2>/dev/null | head -1 \
    | sed 's/[[:space:]]*#.*$//; s/[[:space:]]*$//'
}

# busybox is only needed for httpd/wget (serving the page); grep and sed are
# toybox on every Android since 6.0, so they are used directly.
find_bb() {
  local c
  for c in "$(cfg BB)" /vendor/bin/busybox /data/adb/magisk/busybox \
           /data/adb/ksu/bin/busybox /data/adb/ap/bin/busybox \
           /system/xbin/busybox /system/bin/busybox /data/data/com.termux/files/usr/bin/busybox; do
    case "$c" in ""|auto) continue ;; esac
    [ -x "$c" ] && { echo "$c"; return 0; }
  done
  command -v busybox 2>/dev/null
}
BB=$(find_bb)

LIMIT=$(cfg LIMIT); LIMIT=${LIMIT:-600}
# grace period for the 1st, 2nd, ... quiz of the day; last entry repeats
LIMITS=$(cfg LIMITS); LIMITS=${LIMITS:-$LIMIT}
STATE=$W/state
GRADE=$(cfg GRADE); GRADE=${GRADE:-5}
N=$(cfg N); N=${N:-3}
STEP=$(cfg STEP); STEP=${STEP:-10}
QUIZ_TIMEOUT=$(cfg QUIZ_TIMEOUT); QUIZ_TIMEOUT=${QUIZ_TIMEOUT:-420}
MAX_TIMEOUTS=$(cfg MAX_TIMEOUTS); MAX_TIMEOUTS=${MAX_TIMEOUTS:-3}
TIMEOUT_ACTION=$(cfg TIMEOUT_ACTION); TIMEOUT_ACTION=${TIMEOUT_ACTION:-sleep}
PORT=$(cfg PORT); PORT=${PORT:-8088}
DBG=$(cfg DBG); DBG=${DBG:-0}
BROWSER=$(cfg BROWSER); BROWSER=${BROWSER:-com.tcl.browser}
MODE=$(cfg MODE); MODE=${MODE:-except}
AWAY_RESET=$(cfg AWAY_RESET); AWAY_RESET=${AWAY_RESET:-1800}

WATCH=$(cfg WATCH)
[ -z "$WATCH" ] && WATCH="com.tcl.vod com.tcl.tv"
WATCH=" $WATCH "

# Fallback only: config.sh always carries the real list.
SKIP=$(cfg SKIP)
[ -z "$SKIP" ] && SKIP="com.android.systemui com.android.settings com.android.tv.settings com.android.tvlauncher com.android.packageinstaller com.google.android.packageinstaller com.google.android.tvlauncher com.google.android.apps.tv.launcherx com.google.android.leanbacklauncher com.google.android.tungsten.setupwraith"
SKIP=" $SKIP "

log() {
  echo "$(date '+%m-%d %H:%M:%S') $*" >> "$LOG"
  chmod 644 "$LOG" 2>/dev/null
}

# Quiz count since local midnight -> which grace period applies now.
save_state() {
  printf 'd=%s\nn=%s\nt=%s\n' "$1" "$2" "$(date +%s)" > "$STATE" 2>/dev/null
  chmod 644 "$STATE" 2>/dev/null
}

# 掉电后 RTC 会跳回 2000-01-01，对时后再跳回来。这种跳变不能当"跨日"处理，
# 否则拔一下电源就把当天次数清零了。
date_ok() {
  local y=${1%%-*}
  case "$y" in ''|*[!0-9]*) return 1 ;; esac
  [ "$y" -ge 2024 ] && [ "$y" -le 2100 ]
}

# 掉电后 RTC 读 2000，NTP 要几十秒才把它拨到当天，中间可能分几步跳。
# 启动后等它安静下来（两拍差值接近 sleep 时长）再取时间，之后就不用再猜了。
wait_clock() {
  local i=0 a b same=0
  sleep 8                       # 先让网络/NTP 跑第一轮
  while [ "$i" -lt 30 ]; do
    a=$(date +%s)
    sleep 3
    b=$(date +%s)
    # 时钟正常走 = 两拍差就是这 3 秒；被拨动时会跳成几百秒
    if [ $((b - a)) -ge 2 ] && [ $((b - a)) -le 8 ] && date_ok "$(date +%Y-%m-%d)"; then
      same=$((same + 1))
      if [ "$same" -ge 3 ]; then
        log "clock settled after $((i * 3 + 11))s"
        return 0
      fi
    else
      same=0
    fi
    i=$((i + 1))
  done
  log "clock not settled in 100s, using it as is"
  return 1
}

load_count() {
  local today d n
  today=$(date +%Y-%m-%d)
  d=""; n=0
  if [ -f "$STATE" ]; then
    d=$(sed -n 's/^d=//p' "$STATE" | head -1)
    n=$(sed -n 's/^n=//p' "$STATE" | head -1)
  fi
  case "$n" in ''|*[!0-9]*) n=0 ;; esac
  if [ "$d" != "$today" ]; then
    # 只在新日期"确实更晚且两个日期都可信"时清零
    if date_ok "$d" && date_ok "$today" && [ "$today" \> "$d" ]; then
      log "new day $today (was $d) -> count reset"
      n=0
    fi
    save_state "$today" "$n"
  fi
  echo "$n"
}

# limit_for 3 with LIMITS="600 600 480 480 300" -> 480 (3rd quiz of the day)
limit_for() {
  local k=$1 i=0 v last=""
  for v in $LIMITS; do
    i=$((i + 1))
    last=$v
    [ "$i" -ge "$k" ] && { echo "$v"; return; }
  done
  echo "${last:-$LIMIT}"
}

# "dumpsys window windows" exists up to Android 11; newer builds only take
# "dumpsys window". Line looks like:
#   mCurrentFocus=Window{1a2b3c u0 com.foo/com.foo.MainActivity}
focus_line() {
  local l
  l=$(dumpsys window windows 2>/dev/null | grep 'mCurrentFocus=' | head -1)
  [ -z "$l" ] && l=$(dumpsys window 2>/dev/null | grep 'mCurrentFocus=' | head -1)
  echo "$l"
}

# full component, e.g. com.tcl.vod/com.tcl.vod.MainActivity
# Parsed with sed: the brace in Window{...} is awkward to strip portably.
fgc() {
  local c
  c=$(focus_line)
  [ -z "$c" ] && { echo null; return; }
  echo "$c" | sed 's/.*mCurrentFocus=//; s/}.*//; s/.* //'
}

fg() {
  local c
  c=$(fgc)
  echo "${c%%/*}"
}

# Is the foreground app "screen time"? MODE=except (default) counts everything
# except SKIP; MODE=watch counts only the WATCH whitelist.
counted() {
  local cur="$1"
  [ -z "$cur" ] && return 1
  [ "$cur" = "null" ] && return 1
  if [ "$MODE" = "watch" ]; then
    case "$WATCH" in *" $cur "*) return 0 ;; *) return 1 ;; esac
  fi
  case "$SKIP" in *" $cur "*) return 1 ;; *) return 0 ;; esac
}

screen_on() {
  dumpsys power 2>/dev/null | grep -q "mWakefulness=Awake"
}

# Bring the app the kid came from back to the front. The task is usually still
# alive, so "am start -n pkg/act" just un-hides it (no restart, video keeps
# playing); if that fails, relaunch through the launcher.
resume_prev() {
  local comp="$1" pkg
  case "$comp" in ''|null) return ;; esac
  case "$comp" in "$BROWSER"/*) return ;; esac
  pkg=${comp%%/*}
  am start -n "$comp" >/dev/null 2>&1
  sleep 2
  [ "$(fg)" = "$pkg" ] && return
  monkey -p "$pkg" -c android.intent.category.LAUNCHER 1 >/dev/null 2>&1
  sleep 2
}

start_server() {
  [ -z "$BB" ] && return 1
  $BB httpd -p "$PORT" -h "$W" 2>/dev/null
  sleep 1
}

# The page lives on 127.0.0.1:PORT; if httpd died the browser falls back to its
# own home page and the kid sees a sitemap instead of a question.
server_up() {
  [ -z "$BB" ] && return 1
  $BB wget -q -O /dev/null -T 3 "http://127.0.0.1:$PORT/index.html" 2>/dev/null && return 0
  start_server
}

# Focus flaps while the page is loading (the app underneath grabs it back for a
# moment), so trust the task stack instead. "am stack list" is gone in newer
# releases; there the activity dump is used, and as a last resort a recent
# foreground hit within 20s.
LAST_BROWSER_TS=""
quiz_visible() {
  local st now
  [ -z "$BROWSER" ] && return 0     # never reopen in a loop when unset
  st=$(am stack list 2>/dev/null)
  case "$st" in
    *taskId*)
      echo "$st" | grep "$BROWSER/" | grep -q "visible=true"
      return $?
      ;;
  esac
  if dumpsys activity activities 2>/dev/null | grep -q "ResumedActivity.*$BROWSER"; then
    return 0
  fi
  now=$(date +%s)
  [ -n "$LAST_BROWSER_TS" ] && [ $((now - LAST_BROWSER_TS)) -le 20 ]
}

open_quiz() {
  local extra=""
  server_up || return 1
  [ "$DBG" = "1" ] && extra="&dbg=1"
  am start -a android.intent.action.VIEW -d "http://127.0.0.1:$PORT/?g=$GRADE&n=$N&t=$(date +%s)$extra" >/dev/null 2>&1
}

run_quiz() {
  local prev round start now el cur miss
  if ! server_up; then
    log "quiz aborted: no page server (busybox/BB missing, see README)"
    return 2
  fi
  prev=$(fgc)
  log "quiz start (grade=$GRADE) prev=$prev"
  rm -f "$W/pass.stamp"
  round=0
  while true; do
    round=$((round + 1))
    open_quiz
    start=$(date +%s); miss=0
    while true; do
      sleep 3
      now=$(date +%s); el=$((now - start))
      if [ -f "$W/pass.stamp" ]; then
        log "quiz passed in ${el}s (round $round)"
        am force-stop "$BROWSER" >/dev/null 2>&1
        sleep 1
        resume_prev "$prev"
        log "resumed -> $(fg) (want ${prev})"
        return 0
      fi
      if [ "$el" -gt "$QUIZ_TIMEOUT" ]; then
        am force-stop "$BROWSER" >/dev/null 2>&1
        sleep 2
        if screen_on; then
          if [ "$round" -ge "$MAX_TIMEOUTS" ]; then
            log "quiz timeout ${el}s (round $round) -> give up, nobody answered"
            return 3
          fi
          log "quiz timeout ${el}s (round $round) -> reopen"
          break
        fi
        log "quiz timeout ${el}s, screen off -> abort round"
        return 2
      fi
      cur=$(fg)
      [ "$cur" = "$BROWSER" ] && LAST_BROWSER_TS=$(date +%s)
      # 屏幕关了就安静等着，别把电视叫醒
      if [ -z "$cur" ] || [ "$cur" = "null" ]; then
        miss=0
        sleep 3
        continue
      fi
      if ! quiz_visible; then
        miss=$((miss + 1))
        if [ "$miss" -ge 2 ]; then
          if screen_on; then
            log "quiz left by '$cur' at ${el}s -> reopen"
            open_quiz
          else
            log "quiz left by '$cur' at ${el}s, screen off -> abort round"
            am force-stop "$BROWSER" >/dev/null 2>&1
            return 2
          fi
          miss=0
        fi
      else
        miss=0
      fi
    done
  done
}

wait_clock
day=$(date +%Y-%m-%d)
cnt=$(load_count)
log "gate up: mode=$MODE grade=$GRADE day=$day count=$cnt limits=[$LIMITS]"
log "env: bb=${BB:-none} browser=$BROWSER port=$PORT step=${STEP}s timeout=${QUIZ_TIMEOUT}s"
server_up
acc=0
away=0
while true; do
  if [ -f "$W/pause" ]; then
    acc=0; away=0
    sleep $STEP
    continue
  fi
  d=$(date +%Y-%m-%d)
  if [ "$d" != "$day" ]; then
    if date_ok "$day" && date_ok "$d" && [ "$d" \> "$day" ]; then
      cnt=0; acc=0; away=0
      log "midnight rollover $day -> $d, count reset, limit $(limit_for 1)s"
    else
      log "clock changed $day -> $d, count kept at $cnt"
    fi
    save_state "$d" "$cnt"
    day=$d
  fi
  # manual override: "set=N" in the state file is adopted once, then dropped
  ov=$(sed -n 's/^set=//p' "$STATE" 2>/dev/null | head -1)
  case "$ov" in
    ''|*[!0-9]*) ;;
    *)
      cnt=$ov
      save_state "$day" "$cnt"
      log "count set to $cnt by hand -> next limit $(limit_for $((cnt + 1)))s"
      ;;
  esac
  LIM=$(limit_for $((cnt + 1)))
  cur=$(fg)
  # Accumulate while watching; leaving the screen only pauses the count, and
  # resets it after AWAY_RESET seconds away (a quick trip home is not a reset).
  if counted "$cur"; then
    acc=$((acc + STEP))
    away=0
  else
    away=$((away + STEP))
    [ "$away" -ge "$AWAY_RESET" ] && acc=0
  fi
  [ "$DBG" = "1" ] && log "tick cur=$cur acc=$acc away=$away n=$cnt limit=$LIM"
  if [ "$acc" -ge "$LIM" ]; then
    run_quiz
    rc=$?
    if [ "$rc" -eq 0 ]; then
      cnt=$((cnt + 1))
      save_state "$day" "$cnt"
      log "quiz #$cnt passed today -> next limit $(limit_for $((cnt + 1)))s"
    elif [ "$rc" -eq 3 ]; then
      log "no answer in $MAX_TIMEOUTS rounds -> $TIMEOUT_ACTION"
      case "$TIMEOUT_ACTION" in
        sleep) /system/bin/input keyevent 223 >/dev/null 2>&1 ;;
        home)  /system/bin/input keyevent 3 >/dev/null 2>&1 ;;
      esac
    fi
    acc=0; away=0
  fi
  sleep $STEP
done
