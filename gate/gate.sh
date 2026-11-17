#!/system/bin/sh
# 看门狗主循环：计时、到点弹题、答题后放行。
# 所有函数在 lib.sh，设备相关参数在 config.sh。
. "$(dirname "$0")/lib.sh"

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
