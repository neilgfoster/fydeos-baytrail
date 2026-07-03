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
    [ -e "$b" ] || { echo "(none)"; break; }
    echo "-- $(basename "$b"): type=$(cat "$b/type" 2>/dev/null) bright=$(cat "$b/brightness" 2>/dev/null) max=$(cat "$b/max_brightness" 2>/dev/null) actual=$(cat "$b/actual_brightness" 2>/dev/null)"
  done

  echo "===== /sys/class/pwm chips ====="
  for p in /sys/class/pwm/*; do
    [ -e "$p" ] || { echo "(none)"; break; }
    echo "-- $(basename "$p"): npwm=$(cat "$p/npwm" 2>/dev/null) -> $(readlink -f "$p" 2>/dev/null)"
    for ch in "$p"/pwm*; do [ -e "$ch" ] || continue; echo "     $(basename "$ch"): enable=$(cat "$ch/enable" 2>/dev/null) duty=$(cat "$ch/duty_cycle" 2>/dev/null) period=$(cat "$ch/period" 2>/dev/null)"; done
  done

  echo "===== i2c adapters (adapter name = the bus) ====="
  for a in /sys/class/i2c-adapter/*; do [ -e "$a" ] || { echo "(none)"; break; }; echo "-- $(basename "$a"): $(cat "$a/name" 2>/dev/null)"; done

  echo "===== /sys/bus/i2c/devices (bound driver shown) ====="
  for d in /sys/bus/i2c/devices/*; do
    [ -e "$d" ] || { echo "(none)"; break; }
    echo "-- $(basename "$d"): name=$(cat "$d/name" 2>/dev/null) driver=$(basename "$(readlink -f "$d/driver" 2>/dev/null)" 2>/dev/null)"
  done

  echo "===== ACPI platform devices INT33FD(CrystalCove) INT33F4(AXP288) 80860F09(LPSS-PWM) status/driver ====="
  for id in INT33FD INT33F4 INT33F5 80860F09 808622A8; do
    for d in /sys/bus/platform/devices/${id}:* /sys/bus/acpi/devices/${id}:*; do
      [ -e "$d" ] || continue
      echo "-- $(basename "$d"): driver=$(basename "$(readlink -f "$d/driver" 2>/dev/null)" 2>/dev/null) status=$(cat "$d/status" 2>/dev/null)"
    done
  done

  echo "===== MFD / regulator (AXP288) ====="
  ls -1 /sys/class/regulator/ 2>/dev/null | head -30
  for r in /sys/class/regulator/regulator.*; do [ -e "$r" ] || break; echo "-- $(cat "$r/name" 2>/dev/null): state=$(cat "$r/state" 2>/dev/null) $(cat "$r/microvolts" 2>/dev/null)uV"; done

  echo "===== i915 DRM connectors / panel ====="
  for c in /sys/class/drm/card*/card*-*; do
    [ -e "$c" ] || continue
    echo "-- $(basename "$c"): status=$(cat "$c/status" 2>/dev/null) enabled=$(cat "$c/enabled" 2>/dev/null)"
  done

  echo "===== loaded modules (pwm/pmic/backlight/regulator/i915) ====="
  lsmod 2>/dev/null | grep -iE 'pwm|crystal|axp|pmic|backlight|regulator|i915|lpss' || echo "(none matched / no lsmod)"

  echo "===== kernel config (backlight/pwm/pmic) for gap-finding ====="
  ( zcat /proc/config.gz 2>/dev/null || cat /boot/config-* 2>/dev/null ) | grep -iE 'PWM_CRC|PWM_LPSS|CRYSTAL_COVE|AXP288|PMIC_OPREGION|BACKLIGHT_PWM|BACKLIGHT_LP855|GPIO_CRYSTAL|MFD_INTEL_LPSS' | sort || echo "(config not exposed)"

  echo "===== dmesg backlight/pwm/pmic/crc/DSI/i915 (full, not tail) ====="
  dmesg 2>/dev/null | grep -iE 'backlight|pwm|crystal[_ ]?cove|axp288|pmic|opregion|int33f|80860f09|i915|DSI|panel|brightness|lpss' || echo "(no matches)"
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

# If no backlight device dimmed the panel, probe the PWM chips directly: does
# driving the raw PWM physically dim the panel? If yes -> HW path works, we just
# need a backlight driver wired to it. If no -> wrong PWM / panel-native path.
if ! ls /sys/class/backlight/* >/dev/null 2>&1; then
  say "no backlight devices — trying RAW PWM chips directly"
  for p in /sys/class/pwm/*; do
    [ -e "$p" ] || continue
    pname=$(basename "$p"); npwm=$(cat "$p/npwm" 2>/dev/null)
    ch=0; while [ "$ch" -lt "${npwm:-0}" ]; do
      echo "$ch" > "$p/export" 2>>"$TRACE"
      pd="$p/pwm$ch"; [ -e "$pd" ] || { ch=$((ch+1)); continue; }
      # ~1kHz period; try 20% then back to 100% duty so a dim is visible
      echo 1000000 > "$pd/period" 2>>"$TRACE"
      echo 200000  > "$pd/duty_cycle" 2>>"$TRACE"
      echo 1       > "$pd/enable" 2>>"$TRACE"
      say ">>> RAW $pname/pwm$ch @20% duty — WATCH SCREEN (6s)"
      sleep 6
      echo 1000000 > "$pd/duty_cycle" 2>>"$TRACE"
      say "    RAW $pname/pwm$ch @100% duty"
      sleep 2
      echo 0 > "$pd/enable" 2>>"$TRACE"
      echo "$ch" > "$p/unexport" 2>>"$TRACE"
      ch=$((ch+1))
    done
  done
  say "raw pwm test done"
fi
finish "=== BACKLIGHT DIAG DONE — tell me which device/PWM (if any) dimmed the screen ===" 12
