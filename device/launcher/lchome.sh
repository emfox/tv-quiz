#!/system/bin/sh
# TCL's framework brings its own boot package to front on every boot,
# ignoring the standard home_activity setting. Bring the user's launcher
# back once the boot has settled.

i=0
while [ "$(getprop sys.boot_completed)" != "1" ]; do
    sleep 1
    i=$((i + 1))
    [ "$i" -gt 120 ] && exit 0
done

sleep 10
am start -a android.intent.action.MAIN -c android.intent.category.HOME
