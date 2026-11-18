#!/usr/bin/env bash
# device/su：产物必须是设备真能跑的形态（32 位 ARM、静态、非 PIE、不链 libc）。
set -u
. "$(dirname "$0")/lib.sh"

T=$(mktemp -d)
trap 'rm -rf "$T"' EXIT

if ! command -v arm-linux-gnueabihf-gcc >/dev/null 2>&1; then
  echo "  跳过：没有 arm-linux-gnueabihf-gcc（apt install gcc-arm-linux-gnueabihf）"
  summary "su"
  exit 0
fi

if ! make -C "$ROOT/device/su" >/dev/null 2>&1; then
  fail "编译" "成功" "失败"
  summary "su"
  exit 1
fi

file "$ROOT/device/su/su" > "$T/info"
yes "ELF 32 位" "grep -q 'ELF 32-bit' '$T/info'"
yes "机器是 ARM（设备 ABI = armeabi-v7a）" "grep -q 'ARM, EABI' '$T/info'"
yes "静态链接（Android 上没有 glibc）" "grep -q 'statically linked' '$T/info'"
no "不是 PIE（静态 PIE 要自举重定位，我们不提供）" "grep -q 'pie executable' '$T/info'"

size=$(stat -c %s "$ROOT/device/su/su" 2>/dev/null || echo 999999)
yes "体积 < 8 KB（链进 libc 就会上几百 KB）" "[ $size -lt 8192 ]"

summary "su"
