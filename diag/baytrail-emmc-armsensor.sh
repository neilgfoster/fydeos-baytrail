#!/bin/sh
# Iconia W4-820 — arm/disarm the eMMC to run the pre-init sensor loader (PID 1,
# off USB). Idempotent toggle:
#   - if eMMC grub init already points at baytrail-sensor-boot.sh -> DISARM
#     (restore init=/sbin/init).
#   - else -> ARM: copy baytrail-sensor-boot.sh onto eMMC /sbin, set eMMC grub
#     init= to it. Next eMMC boot force-loads the HID-sensor stack then execs the
#     real init -> boots to OOBE with accel_3d up. Try rotating the tablet.
# The wrapper script must be on the USB rootfs at /sbin/baytrail-sensor-boot.sh.
export PATH=/usr/sbin:/usr/bin:/sbin:/bin
CON=/dev/tty1
TRACE=/baytrail-emmc-armsensor.log
EROOTA_MNT=/mnt/e-root
EESP_MNT=/mnt/e-esp
WRAP=baytrail-sensor-boot.sh

mount -t proc proc /proc 2>/dev/null
mount -t sysfs sys /sys 2>/dev/null
mount -t devtmpfs dev /dev 2>/dev/null
mount -t tmpfs run /run 2>/dev/null
mount -o remount,rw / 2>/dev/null || true

say() { _m="[$(date -u '+%H:%M:%S' 2>/dev/null)] $*"; echo "ICONIA $_m" > "$CON" 2>/dev/null||true; echo "$_m" >> "$TRACE" 2>/dev/null||true; sync 2>/dev/null||true; }
finish() { say "$1"; sync; sleep "${2:-10}"; poweroff -f 2>/dev/null; echo o > /proc/sysrq-trigger 2>/dev/null; while true; do sleep 60; done; }
partdev() { case "$1" in *[0-9]) echo "$1p$2";; *) echo "$1$2";; esac; }
find_emmc() { for d in /sys/block/mmcblk*; do b=$(basename "$d"); case "$b" in *boot*|*rpmb*) continue;; esac; sz=$(cat "$d/size" 2>/dev/null); [ "${sz:-0}" -gt 100000000 ] && { echo "/dev/$b"; return 0; }; done; return 1; }

n=0; while [ "$n" -lt 6 ]; do echo "" > "$CON"; echo "#### ICONIA eMMC ARM SENSOR ####" > "$CON"; n=$((n+1)); done
say "=== baytrail-emmc-armsensor.sh PID $$ ==="
mkdir -p /run/udev; udevd --daemon 2>/dev/null || /lib/systemd/systemd-udevd --daemon 2>/dev/null
udevadm trigger --action=add 2>/dev/null; udevadm settle --timeout=10 2>/dev/null

DRV=/sys/bus/platform/drivers/sdhci-acpi; i=0; TARGET="$(find_emmc)"
while [ -z "$TARGET" ] && [ "$i" -lt 40 ]; do
  for base in 80860F14:00 80860F14:01; do [ -e "/sys/bus/platform/devices/$base" ] || continue; echo "$base" > "$DRV/unbind" 2>/dev/null; echo "$base" > "$DRV/bind" 2>/dev/null; done
  udevadm trigger --action=add 2>/dev/null; udevadm settle --timeout=5 2>/dev/null; sleep 2; i=$((i+1)); TARGET="$(find_emmc)"; say "ensure eMMC try $i: ${TARGET:-absent}"
done
[ -n "$TARGET" ] || finish "FATAL: no eMMC after $i tries — power-cycle & retry" 20
say "eMMC = $TARGET"

EROOTA="$(partdev "$TARGET" 3)"; EESP="$(partdev "$TARGET" 12)"
mkdir -p "$EROOTA_MNT" "$EESP_MNT"
mount "$EROOTA" "$EROOTA_MNT" 2>/dev/null || finish "FATAL: cannot mount eMMC ROOT-A $EROOTA" 20
mount -o remount,rw "$EROOTA_MNT" 2>/dev/null
mount "$EESP" "$EESP_MNT" 2>/dev/null || finish "FATAL: cannot mount eMMC ESP $EESP" 20

GRUB="$EESP_MNT/boot/grub/grub.cfg"
if grep -q "$WRAP" "$GRUB" 2>/dev/null; then
  sed -i 's#init=[^ ]*#init=/sbin/init#' "$GRUB"
  MODE="DISARMED — eMMC restored to init=/sbin/init"
else
  cp -f "/sbin/$WRAP" "$EROOTA_MNT/sbin/$WRAP" 2>>"$TRACE" && chmod +x "$EROOTA_MNT/sbin/$WRAP"
  sed -i "s#init=[^ ]*#init=/sbin/$WRAP#" "$GRUB"
  MODE="ARMED — next eMMC boot force-loads HID sensors then boots to OOBE. Try rotating!"
fi
grep -o 'init=[^ ]*' "$GRUB" >> "$TRACE" 2>&1
sync
umount "$EESP_MNT" 2>/dev/null; umount "$EROOTA_MNT" 2>/dev/null
finish "=== $MODE ===" 12
