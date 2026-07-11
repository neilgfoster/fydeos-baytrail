#!/bin/sh
# Iconia W4-820 — install the audio diag onto the eMMC and point eMMC grub init=
# at it (PID 1, off USB). One-shot: baytrail-audio-diag.sh self-restores
# init=/sbin/init when it finishes, so the eMMC boots normally again afterward.
# The diag must be present on the USB rootfs at /sbin/baytrail-audio-diag.sh.
export PATH=/usr/sbin:/usr/bin:/sbin:/bin
CON=/dev/tty1
TRACE=/baytrail-emmc-armaudio.log
EROOTA_MNT=/mnt/e-root
EESP_MNT=/mnt/e-esp
DIAG=baytrail-audio-diag.sh

mount -t proc proc /proc 2>/dev/null
mount -t sysfs sys /sys 2>/dev/null
mount -t devtmpfs dev /dev 2>/dev/null
mount -t tmpfs run /run 2>/dev/null
mount -o remount,rw / 2>/dev/null || true

say() { _m="[$(date -u '+%H:%M:%S' 2>/dev/null)] $*"; echo "ICONIA $_m" > "$CON" 2>/dev/null||true; echo "$_m" >> "$TRACE" 2>/dev/null||true; sync 2>/dev/null||true; }
finish() { say "$1"; sync; sleep "${2:-10}"; poweroff -f 2>/dev/null; echo o > /proc/sysrq-trigger 2>/dev/null; while true; do sleep 60; done; }
partdev() { case "$1" in *[0-9]) echo "$1p$2";; *) echo "$1$2";; esac; }
find_emmc() { for d in /sys/block/mmcblk*; do b=$(basename "$d"); case "$b" in *boot*|*rpmb*) continue;; esac; sz=$(cat "$d/size" 2>/dev/null); [ "${sz:-0}" -gt 100000000 ] && { echo "/dev/$b"; return 0; }; done; return 1; }

n=0; while [ "$n" -lt 6 ]; do echo "" > "$CON"; echo "#### ICONIA eMMC ARM AUDIO ####" > "$CON"; n=$((n+1)); done
say "=== baytrail-emmc-armaudio.sh PID $$ ==="
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
cp -f "/sbin/$DIAG" "$EROOTA_MNT/sbin/$DIAG" 2>>"$TRACE" && chmod +x "$EROOTA_MNT/sbin/$DIAG"
sed -i "s#init=[^ ]*#init=/sbin/$DIAG#" "$EESP_MNT/boot/grub/grub.cfg" 2>>"$TRACE"
grep -o 'init=[^ ]*' "$EESP_MNT/boot/grub/grub.cfg" >> "$TRACE" 2>&1
sync
umount "$EESP_MNT" 2>/dev/null; umount "$EROOTA_MNT" 2>/dev/null
finish "=== ARMED — boot the eMMC (USB removed): it runs the audio tone test & self-restores ===" 12
