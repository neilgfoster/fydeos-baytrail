#!/bin/sh
# Iconia W4-820 — accelerometer/sensor diagnostic (PID 1). The accel ACPI device
# SMO91D0 has NO matching driver in the kernel tree (only SMO8500/SMO8840 do), so
# it never enumerates -> no auto-rotate. This dumps the ACPI _HID/_CID (compatible
# id), i2c/iio state and dmesg so we know which IIO accel driver (kxcjk-1013,
# bmc150, st_accel, mxc4005 ...) to enable + whether a _CID lets it bind. Runs off
# the USB (same hardware the tablet enumerates); does NOT touch the eMMC.
export PATH=/usr/sbin:/usr/bin:/sbin:/bin
CON=/dev/tty1
TRACE=/iconia-sensor-diag.log

mount -t proc proc /proc 2>/dev/null
mount -t sysfs sys /sys 2>/dev/null
mount -t devtmpfs dev /dev 2>/dev/null
mount -t tmpfs run /run 2>/dev/null
mount -o remount,rw / 2>/dev/null || true

say() { _m="[$(date -u '+%H:%M:%S' 2>/dev/null)] $*"; echo "ICONIA $_m" > "$CON" 2>/dev/null||true; echo "$_m" >> "$TRACE" 2>/dev/null||true; sync 2>/dev/null||true; }
finish() { say "$1"; sync; sleep "${2:-10}"; poweroff -f 2>/dev/null; echo o > /proc/sysrq-trigger 2>/dev/null; while true; do sleep 60; done; }

n=0; while [ "$n" -lt 6 ]; do echo "" > "$CON"; echo "###### ICONIA SENSOR DIAG ######" > "$CON"; n=$((n+1)); done
say "=== iconia-sensor-diag.sh PID $$ ==="
mkdir -p /run/udev; udevd --daemon 2>/dev/null || /lib/systemd/systemd-udevd --daemon 2>/dev/null
udevadm trigger --action=add 2>/dev/null; udevadm settle --timeout=15 2>/dev/null
sleep 3
# Explicitly load the HID-sensor stack from the DEFAULT module path (= the booted
# rootfs, so LoadPin permits it). No-op on the USB rootfs (modules absent); on the
# eMMC #9 rootfs these are present and this forces the accel to enumerate.
for m in hid-sensor-hub hid-sensor-accel-3d hid-sensor-incl-3d hid-sensor-rotation hid-sensor-als; do
  modprobe "$m" 2>>"$TRACE" && say "modprobe $m OK" || say "modprobe $m (absent/failed)"
done
udevadm trigger --action=add 2>/dev/null; udevadm settle --timeout=10 2>/dev/null; sleep 2

{
  echo "===== ACPI devices with SMO*/KIOX*/BOSC*/accel-ish HIDs ====="
  for d in /sys/bus/acpi/devices/*; do
    [ -e "$d" ] || continue
    hid=$(cat "$d/hid" 2>/dev/null)
    case "$hid" in
      SMO*|KIOX*|BOSC*|BMA*|BMC*|MXC*|KXCJ*|STK*|INVN*|ACCE*|ST*) ;;
      *) continue;;
    esac
    echo "-- $(basename "$d"): hid=$hid"
    echo "     modalias=$(cat "$d/modalias" 2>/dev/null)"
    echo "     path=$(cat "$d/path" 2>/dev/null)  status=$(cat "$d/status" 2>/dev/null)"
    for cf in "$d"/hid "$d"/uid "$d"/adr; do [ -e "$cf" ] && echo "     $(basename "$cf")=$(cat "$cf" 2>/dev/null)"; done
  done

  echo "===== SMO91D0 device detail (the accel) ====="
  for d in /sys/bus/acpi/devices/SMO91D0:* /sys/bus/i2c/devices/i2c-SMO91D0:*; do
    [ -e "$d" ] || continue
    echo "-- $d"
    echo "     modalias=$(cat "$d/modalias" 2>/dev/null)"
    echo "     name=$(cat "$d/name" 2>/dev/null)"
    echo "     driver=$(readlink "$d/driver" 2>/dev/null)"
    ls -1 "$d" 2>/dev/null | tr '\n' ' '; echo
  done

  echo "===== HID devices (group/driver) + SMO91D0 report descriptor ====="
  for h in /sys/bus/hid/devices/*; do
    [ -e "$h" ] || { echo "(none)"; break; }
    hn=$(cat "$h/uevent" 2>/dev/null | grep -E 'HID_NAME|HID_ID' | tr '\n' ' ')
    echo "-- $(basename "$h"): driver=$(readlink "$h/driver" 2>/dev/null | sed 's#.*/##') group=$(cat "$h/group" 2>/dev/null) $hn"
  done
  echo "--- report_descriptor of the SMO91D0 HID node (hex) ---"
  for h in /sys/bus/hid/devices/*91D1*; do
    [ -e "$h/report_descriptor" ] || continue
    od -An -tx1 "$h/report_descriptor" 2>/dev/null
    echo "--- usage-page 0x20 (HID Sensor) present in descriptor? ---"
    od -An -tx1 "$h/report_descriptor" 2>/dev/null | grep -q ' 05 20' && echo "YES (standard HID sensor usage page found)" || echo "NO (no 05 20 -> vendor/custom, sensor-hub won't claim it)"
  done

  echo "===== /sys/bus/iio/devices ====="
  for d in /sys/bus/iio/devices/*; do [ -e "$d" ] || { echo "(none)"; break; }; echo "-- $(basename "$d"): name=$(cat "$d/name" 2>/dev/null)"; done

  echo "===== loaded IIO/accel modules ====="
  lsmod 2>/dev/null | grep -iE 'iio|kxcjk|bmc150|st_accel|mxc|accel|industrialio' || echo "(none)"

  echo "===== dmesg accel/iio/SMO/kiox/kxcjk/bmc150 ====="
  dmesg 2>/dev/null | grep -iE 'iio|accel|SMO|kiox|kxcjk|bmc150|st_accel|mxc4005|gyro|magn|orient' || echo "(no matches)"
} >> "$TRACE" 2>&1
sync

finish "=== SENSOR DIAG DONE — send me the log (need the SMO91D0 modalias/_CID) ===" 12
