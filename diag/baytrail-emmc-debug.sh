#!/bin/sh
# Iconia W4-820 — re-inject a DEBUG+QUIRK grub.cfg onto the eMMC ESP (PID 1).
#
# Purpose: make the eMMC boot reliable / diagnosable. The kernel's eMMC bring-up
# is intermittent (~1-in-3 boots enumerate mmcblk0) — a generic/trimmed kernel
# driving Bay Trail eMMC worse than the OEM Windows driver. This edits the eMMC
# boot cmdline to:
#   * sdhci.debug_quirks2=0x40  -> SDHCI_QUIRK2_BROKEN_HS200: disable HS200 so the
#     eMMC uses a slower, more robust mode (quick reliability experiment).
#   * console=tty1 earlycon=efifb keep_bootcon loglevel=7 -> so if it still hangs
#     we SEE whether it's rootwait (eMMC absent) or something else.
# Non-destructive; edits the existing eMMC /boot/grub/grub.cfg in place (keeps the
# eMMC ROOT-A PARTUUID the installer set). Run via init=/sbin/baytrail-emmc-debug.sh
# from the USB, then remove USB and boot the eMMC.
export PATH=/usr/sbin:/usr/bin:/sbin:/bin
CON=/dev/tty1
TARGET=/dev/mmcblk0
EESP_MNT=/mnt/baytrail-eesp
TRACE=/baytrail-emmc-debug.log

mount -t proc proc /proc 2>/dev/null
mount -t sysfs sys /sys 2>/dev/null
mount -t devtmpfs dev /dev 2>/dev/null
mount -t tmpfs run /run 2>/dev/null
mount -o remount,rw / 2>/dev/null || true

say() { _m="[$(date -u '+%H:%M:%S' 2>/dev/null)] $*"; echo "ICONIA $_m" > "$CON" 2>/dev/null||true; echo "$_m" >> "$TRACE" 2>/dev/null||true; echo "ICONIA: $*" > /dev/kmsg 2>/dev/null||true; sync 2>/dev/null||true; }
finish() { say "$1"; say "powering off in ${2:-10}s"; sync; sleep "${2:-10}"; poweroff -f 2>/dev/null; echo o > /proc/sysrq-trigger 2>/dev/null; while true; do sleep 60; done; }
partdev() { case "$1" in *[0-9]) echo "$1p$2";; *) echo "$1$2";; esac; }

n=0; while [ "$n" -lt 6 ]; do echo "" > "$CON"; echo "#### ICONIA eMMC DEBUG+QUIRK grub ####" > "$CON"; n=$((n+1)); done
say "=== baytrail-emmc-debug.sh PID $$ ==="
mkdir -p /run/udev; udevd --daemon 2>/dev/null || /lib/systemd/systemd-udevd --daemon 2>/dev/null
udevadm trigger --action=add 2>/dev/null; udevadm settle --timeout=30 2>/dev/null
w=0; while [ ! -b "$TARGET" ] && [ "$w" -lt 60 ]; do say "waiting for $TARGET ${w}s"; sleep 3; w=$((w+3)); done
[ -b "$TARGET" ] || finish "FATAL: $TARGET never appeared — power-cycle & retry" 20
say "$TARGET present"

EMMC_ESP="$(partdev "$TARGET" 12)"
mkdir -p "$EESP_MNT"
mount "$EMMC_ESP" "$EESP_MNT" 2>/dev/null || finish "FATAL: cannot mount eMMC ESP" 20
G="$EESP_MNT/boot/grub/grub.cfg"
[ -f "$G" ] || finish "FATAL: $G missing on eMMC ESP" 20

say "--- eMMC grub.cfg BEFORE ---"; grep '  linux' "$G" >> "$TRACE" 2>&1
# only edit if not already applied (idempotent)
grep -q 'sdhci.debug_quirks2' "$G" || sed -i \
  -e 's/loglevel=4/loglevel=7/' \
  -e 's/cros_efi/cros_efi console=tty1 earlycon=efifb keep_bootcon sdhci.debug_quirks2=0x40/' \
  "$G"
say "--- eMMC grub.cfg AFTER ---"; grep '  linux' "$G" >> "$TRACE" 2>&1
sync
umount "$EESP_MNT" 2>/dev/null
finish "=== eMMC grub updated (HS200 off + debug console) — remove USB, boot eMMC ===" 12
