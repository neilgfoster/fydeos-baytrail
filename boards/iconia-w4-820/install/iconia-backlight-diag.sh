#!/bin/sh
# Iconia W4-820 — backlight diagnostic (PID 1). Finds which backlight device
# actually dims the panel and whether writing brightness works at the sysfs
# level. If a device visibly dims -> the fix is just userspace/UI wiring; if
# none dims -> the driver/PWM needs more work. Runs on the USB (new kernel on the
# ESP); does NOT touch the eMMC.
export PATH=/usr/sbin:/usr/bin:/sbin:/bin
CON=/dev/tty1
TRACE=/iconia-backlight-diag.log

mount -t proc proc /proc 2>/dev/null
mount -t sysfs sys /sys 2>/dev/null
mount -t devtmpfs dev /dev 2>/dev/null
mount -t tmpfs run /run 2>/dev/null
mount -o remount,rw / 2>/dev/null || true

say() { _m="[$(date -u '+%H:%M:%S' 2>/dev/null)] $*"; echo "ICONIA $_m" > "$CON" 2>/dev/null||true; echo "$_m" >> "$TRACE" 2>/dev/null||true; sync 2>/dev/null||true; }
finish() { say "$1"; sync; sleep "${2:-10}"; poweroff -f 2>/dev/null; echo o > /proc/sysrq-trigger 2>/dev/null; while true; do sleep 60; done; }

n=0; while [ "$n" -lt 6 ]; do echo "" > "$CON"; echo "###### ICONIA BACKLIGHT DIAG ######" > "$CON"; n=$((n+1)); done
say "=== iconia-backlight-diag.sh PID $$ ==="
mkdir -p /run/udev; udevd --daemon 2>/dev/null || /lib/systemd/systemd-udevd --daemon 2>/dev/null
udevadm trigger --action=add 2>/dev/null; udevadm settle --timeout=15 2>/dev/null
sleep 5

{
  echo "===== /sys/class/backlight devices ====="
  for b in /sys/class/backlight/*; do
    [ -e "$b" ] || continue
    echo "-- $(basename "$b"): type=$(cat "$b/type" 2>/dev/null) bright=$(cat "$b/brightness" 2>/dev/null) max=$(cat "$b/max_brightness" 2>/dev/null) actual=$(cat "$b/actual_brightness" 2>/dev/null)"
  done
  echo "===== dmesg backlight/pwm/crc ====="; dmesg 2>/dev/null | grep -iE 'backlight|pwm|crc|i915.*backlight|DSI' | tail -30
} >> "$TRACE" 2>&1
sync

# visibly test each backlight device so the user can see which dims the panel
for b in /sys/class/backlight/*; do
  [ -e "$b" ] || continue
  name=$(basename "$b"); max=$(cat "$b/max_brightness" 2>/dev/null); [ -n "$max" ] || continue
  low=$((max/5)); [ "$low" -lt 1 ] && low=1
  say ">>> dimming '$name' to $low/$max  — WATCH SCREEN (6s)"
  echo "$low" > "$b/brightness" 2>>"$TRACE"
  sleep 6
  say "    restoring '$name' to $max"
  echo "$max" > "$b/brightness" 2>>"$TRACE"
  sleep 2
done
say "backlight test done"
finish "=== BACKLIGHT DIAG DONE — tell me which device (if any) dimmed the screen ===" 12
