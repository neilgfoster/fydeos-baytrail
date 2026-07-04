#!/bin/sh
# iconia-buttons-install.sh — enable the tablet's hardware buttons on the LIVE
# eMMC system over SSH. Run from the crosh host:
#   scp/ssh the gzipped module to /tmp first, then:
#     ssh -i /tmp/ik root@192.168.1.31 'sh -s' < iconia-buttons-install.sh
# Expects /tmp/soc_button_array.ko.gz already on the tablet (push it alongside).
#
# soc_button_array binds ACPI PNP0C40 (Windows button array) -> KEY_POWER,
# KEY_VOLUMEUP/DOWN, KEY_LEFTMETA (Windows/home), SW_ROTATE_LOCK. It is a module
# on kernel 6.6.76-gabcfb16364e1 (#10+), so we can load & test it with NO reboot.
set -e
KVER=$(uname -r)
MODDIR="/lib/modules/$KVER/kernel/drivers/input/misc"
GZ=/tmp/soc_button_array.ko.gz

[ -f "$GZ" ] || { echo "ERROR: $GZ not found — push it to the tablet first"; exit 1; }

echo "== 1. live test via insmod (no rootfs write) =="
gunzip -c "$GZ" > /tmp/soc_button_array.ko
insmod /tmp/soc_button_array.ko 2>/dev/null || echo "(already loaded?)"
sleep 1
echo "-- dmesg (button array bind) --"
dmesg | grep -iE "soc_button|PNP0C40|gpio.?keys|tablet button" | tail -20 || true
echo "-- input devices now present --"
grep -iE "Name=|Handlers=" /proc/bus/input/devices | grep -iA1 -E "button|tablet|gpio|power|volume" || \
  cat /proc/bus/input/devices | grep -B2 -iE "kbd|event" | tail -30

echo
echo "== 2. persist into rootfs so it autoloads on boot =="
mount -o remount,rw /
mkdir -p "$MODDIR"
cp "$GZ" "$MODDIR/soc_button_array.ko.gz"
depmod "$KVER"
sync
mount -o remount,ro / || true
echo "persisted to $MODDIR/soc_button_array.ko.gz + depmod done"
echo
echo "NEXT: press each button and watch events, e.g.:"
echo "  evtest   # pick the soc_button_array / gpio-keys device, then press buttons"
echo "  (or) cat /dev/input/eventN | hexdump   # if evtest absent"
