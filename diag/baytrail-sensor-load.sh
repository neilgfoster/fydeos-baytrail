#!/bin/sh
# Iconia W4-820 — HID-sensor self-test (PID 1), runs off USB in ONE boot.
# The USB rootfs has OLD modules (no HID-sensor stack) so the accel falls to
# hid-generic. But the STAGED module tar on USB STATE (p1) matches the running
# #9 kernel and DOES contain the HID-sensor modules. Extract the iio+hid subtree,
# depmod against it, modprobe the sensor stack, rebind SMO91D0 off hid-generic,
# and report whether an iio accel_3d device appears. Confirms kernel-side auto-
# rotate support without the multi-boot eMMC dance. Does NOT touch the eMMC.
export PATH=/usr/sbin:/usr/bin:/sbin:/bin
CON=/dev/tty1
TRACE=/baytrail-sensor-load.log
KV=6.6.76-gabcfb16364e1
TAR=modules-baytrail.tar
USTATE_MNT=/mnt/baytrail-ustate
M=/tmp/m

mount -t proc proc /proc 2>/dev/null
mount -t sysfs sys /sys 2>/dev/null
mount -t devtmpfs dev /dev 2>/dev/null
mount -t tmpfs -o size=1g run /run 2>/dev/null
mount -t tmpfs -o size=2g tmp /tmp 2>/dev/null
mount -o remount,rw / 2>/dev/null || true

say() { _m="[$(date -u '+%H:%M:%S' 2>/dev/null)] $*"; echo "ICONIA $_m" > "$CON" 2>/dev/null||true; echo "$_m" >> "$TRACE" 2>/dev/null||true; sync 2>/dev/null||true; }
finish() { say "$1"; sync; sleep "${2:-10}"; poweroff -f 2>/dev/null; echo o > /proc/sysrq-trigger 2>/dev/null; while true; do sleep 60; done; }
partdev() { case "$1" in *[0-9]) echo "$1p$2";; *) echo "$1$2";; esac; }

n=0; while [ "$n" -lt 6 ]; do echo "" > "$CON"; echo "###### ICONIA SENSOR SELF-TEST ######" > "$CON"; n=$((n+1)); done
say "=== baytrail-sensor-load.sh PID $$ (KV=$KV) ==="
mkdir -p /run/udev; udevd --daemon 2>/dev/null || /lib/systemd/systemd-udevd --daemon 2>/dev/null
udevadm trigger --action=add 2>/dev/null; udevadm settle --timeout=15 2>/dev/null
sleep 2

# --- get the staged module tar from USB STATE (p1) ---
USB_DISK="$(rootdev -s -d 2>/dev/null)"; USTATE="$(partdev "$USB_DISK" 1)"
mkdir -p "$USTATE_MNT" "$M"
mount "$USTATE" "$USTATE_MNT" 2>/dev/null || finish "FATAL: cannot mount USB STATE $USTATE" 15
[ -f "$USTATE_MNT/$TAR" ] || finish "FATAL: $TAR not on USB STATE" 15
say "extracting iio+hid module subtree from $TAR ..."
tar xf "$USTATE_MNT/$TAR" -C "$M" \
  "lib/modules/$KV/kernel/drivers/iio" \
  "lib/modules/$KV/kernel/drivers/hid" \
  "lib/modules/$KV/modules.builtin" "lib/modules/$KV/modules.order" 2>>"$TRACE"
# depmod needs a full modules.dep; build it against the extracted subtree
depmod -b "$M" "$KV" 2>>"$TRACE"
say "modprobing HID-sensor stack ..."
for mod in industrialio industrialio-triggered-buffer hid-sensor-iio-common \
           hid-sensor-trigger hid-sensor-hub hid-sensor-accel-3d \
           hid-sensor-incl-3d hid-sensor-rotation; do
  modprobe -d "$M" -S "$KV" "$mod" 2>>"$TRACE" && say "  loaded $mod" || say "  (skip $mod)"
done

# --- rebind the SMO91D0 HID node off hid-generic so hid-sensor-hub can claim it ---
for h in /sys/bus/hid/devices/*91D1*; do
  [ -e "$h" ] || continue
  id=$(basename "$h")
  say "unbinding $id from hid-generic, retriggering ..."
  echo "$id" > /sys/bus/hid/drivers/hid-generic/unbind 2>>"$TRACE"
  sleep 1
  echo "$id" > /sys/bus/hid/drivers/hid-sensor-hub/bind 2>>"$TRACE" || \
    { echo "$id" > /sys/bus/hid/drivers/hid-generic/bind 2>>"$TRACE"; say "  hid-sensor-hub bind FAILED (group mismatch?) -> back to hid-generic"; }
done
udevadm trigger 2>/dev/null; udevadm settle --timeout=10 2>/dev/null; sleep 2

{
  echo "===== loaded modules (post) ====="
  lsmod 2>/dev/null | grep -iE 'hid_sensor|industrialio|accel' || echo "(none)"
  echo "===== SMO91D0 HID driver now ====="
  for h in /sys/bus/hid/devices/*91D1*; do [ -e "$h" ] || continue; echo "-- $(basename "$h"): driver=$(readlink "$h/driver" 2>/dev/null | sed 's#.*/##')"; done
  echo "===== /sys/bus/iio/devices (want an accel_3d!) ====="
  for d in /sys/bus/iio/devices/*; do
    [ -e "$d" ] || { echo "(none)"; break; }
    echo "-- $(basename "$d"): name=$(cat "$d/name" 2>/dev/null)"
    ls "$d" 2>/dev/null | grep -E 'in_accel|mount_matrix|label|location' | sed 's/^/     /'
  done
  echo "===== dmesg hid-sensor/iio/accel ====="
  dmesg 2>/dev/null | grep -iE 'hid-sensor|hid_sensor|iio|accel|SMO91D0' | tail -40 || echo "(none)"
} >> "$TRACE" 2>&1
sync
finish "=== SENSOR SELF-TEST DONE — send me the log (did an iio accel_3d appear?) ===" 12
