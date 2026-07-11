#!/bin/sh
# Iconia W4-820 — pull /iconia-*.log traces off the eMMC ROOT-A onto the USB
# ROOT-A (PID 1, off USB), so they can be read in crosh (eMMC isn't visible to the
# host). Read-only w.r.t. eMMC boot config. Copies to /iconia-emmc-<name>.log on
# the USB rootfs (= our own /). Does not change either grub.
export PATH=/usr/sbin:/usr/bin:/sbin:/bin
CON=/dev/tty1
TRACE=/iconia-emmc-getlog.log
EROOTA_MNT=/mnt/e-root

mount -t proc proc /proc 2>/dev/null
mount -t sysfs sys /sys 2>/dev/null
mount -t devtmpfs dev /dev 2>/dev/null
mount -t tmpfs run /run 2>/dev/null
mount -o remount,rw / 2>/dev/null || true

say() { _m="[$(date -u '+%H:%M:%S' 2>/dev/null)] $*"; echo "ICONIA $_m" > "$CON" 2>/dev/null||true; echo "$_m" >> "$TRACE" 2>/dev/null||true; sync 2>/dev/null||true; }
finish() { say "$1"; sync; sleep "${2:-10}"; poweroff -f 2>/dev/null; echo o > /proc/sysrq-trigger 2>/dev/null; while true; do sleep 60; done; }
partdev() { case "$1" in *[0-9]) echo "$1p$2";; *) echo "$1$2";; esac; }
find_emmc() { for d in /sys/block/mmcblk*; do b=$(basename "$d"); case "$b" in *boot*|*rpmb*) continue;; esac; sz=$(cat "$d/size" 2>/dev/null); [ "${sz:-0}" -gt 100000000 ] && { echo "/dev/$b"; return 0; }; done; return 1; }

n=0; while [ "$n" -lt 6 ]; do echo "" > "$CON"; echo "#### ICONIA eMMC GET-LOG ####" > "$CON"; n=$((n+1)); done
say "=== iconia-emmc-getlog.sh PID $$ ==="
mkdir -p /run/udev; udevd --daemon 2>/dev/null || /lib/systemd/systemd-udevd --daemon 2>/dev/null
udevadm trigger --action=add 2>/dev/null; udevadm settle --timeout=10 2>/dev/null

DRV=/sys/bus/platform/drivers/sdhci-acpi; i=0; TARGET="$(find_emmc)"
while [ -z "$TARGET" ] && [ "$i" -lt 40 ]; do
  for base in 80860F14:00 80860F14:01; do [ -e "/sys/bus/platform/devices/$base" ] || continue; echo "$base" > "$DRV/unbind" 2>/dev/null; echo "$base" > "$DRV/bind" 2>/dev/null; done
  udevadm trigger --action=add 2>/dev/null; udevadm settle --timeout=5 2>/dev/null; sleep 2; i=$((i+1)); TARGET="$(find_emmc)"; say "ensure eMMC try $i: ${TARGET:-absent}"
done
[ -n "$TARGET" ] || finish "FATAL: no eMMC after $i tries — power-cycle & retry" 20
say "eMMC = $TARGET"

EROOTA="$(partdev "$TARGET" 3)"; mkdir -p "$EROOTA_MNT"
mount "$EROOTA" "$EROOTA_MNT" 2>/dev/null || finish "FATAL: cannot mount eMMC ROOT-A $EROOTA" 20
cnt=0
for f in "$EROOTA_MNT"/iconia-*.log; do
  [ -f "$f" ] || continue
  cp -f "$f" "/iconia-emmc-$(basename "$f")" 2>>"$TRACE" && cnt=$((cnt+1))
done
sync
umount "$EROOTA_MNT" 2>/dev/null
finish "=== GOT $cnt log(s) — read /iconia-emmc-iconia-*.log on USB ROOT-A in crosh ===" 12
