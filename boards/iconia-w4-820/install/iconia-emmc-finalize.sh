#!/bin/sh
# Iconia W4-820 — finalize the eMMC install for daily use (PID 1, init= wrapper).
#
# Two fixes, both keyboard-free on the eMMC:
#  1. RE-ENABLE THE UI. During PID-1 install debugging we disabled the UI on the
#     USB rootfs (mv ui.conf ui.conf.disabled) for console visibility; chromeos-
#     install bitwise-copied that rootfs to the eMMC, so the eMMC also has no UI
#     -> boots to console spam, never OOBE. Restore /etc/init/ui.conf on eMMC
#     ROOT-A (mmcblk0p3).
#  2. CLEAN THE GRUB. Strip the debug console (console=tty1/earlycon/keep_bootcon,
#     loglevel 7->4) from the eMMC grub.cfg so OOBE draws cleanly. KEEP
#     sdhci.debug_quirks2=0x40 (the HS200-off quirk that made eMMC enumeration
#     reliable) and the i915 flicker flags.
#
# Run via init=/sbin/iconia-emmc-finalize.sh from the USB, then remove USB and
# boot the eMMC -> should reach OOBE reliably.
export PATH=/usr/sbin:/usr/bin:/sbin:/bin
CON=/dev/tty1
TARGET=/dev/mmcblk0
ROOTA_MNT=/mnt/iconia-eroota
EESP_MNT=/mnt/iconia-eesp
TRACE=/iconia-emmc-finalize.log

mount -t proc proc /proc 2>/dev/null
mount -t sysfs sys /sys 2>/dev/null
mount -t devtmpfs dev /dev 2>/dev/null
mount -t tmpfs run /run 2>/dev/null
mount -o remount,rw / 2>/dev/null || true

say() { _m="[$(date -u '+%H:%M:%S' 2>/dev/null)] $*"; echo "ICONIA $_m" > "$CON" 2>/dev/null||true; echo "$_m" >> "$TRACE" 2>/dev/null||true; echo "ICONIA: $*" > /dev/kmsg 2>/dev/null||true; sync 2>/dev/null||true; }
finish() { say "$1"; say "powering off in ${2:-10}s"; sync; sleep "${2:-10}"; poweroff -f 2>/dev/null; echo o > /proc/sysrq-trigger 2>/dev/null; while true; do sleep 60; done; }
partdev() { case "$1" in *[0-9]) echo "$1p$2";; *) echo "$1$2";; esac; }

n=0; while [ "$n" -lt 6 ]; do echo "" > "$CON"; echo "#### ICONIA eMMC FINALIZE (enable UI) ####" > "$CON"; n=$((n+1)); done
say "=== iconia-emmc-finalize.sh PID $$ ==="
mkdir -p /run/udev; udevd --daemon 2>/dev/null || /lib/systemd/systemd-udevd --daemon 2>/dev/null
udevadm trigger --action=add 2>/dev/null; udevadm settle --timeout=30 2>/dev/null
w=0; while [ ! -b "$TARGET" ] && [ "$w" -lt 60 ]; do say "waiting for $TARGET ${w}s"; sleep 3; w=$((w+3)); done
[ -b "$TARGET" ] || finish "FATAL: $TARGET never appeared — power-cycle & retry" 20
say "$TARGET present"

# 1. re-enable UI on eMMC ROOT-A
EROOTA="$(partdev "$TARGET" 3)"
mkdir -p "$ROOTA_MNT"
if mount "$EROOTA" "$ROOTA_MNT" 2>/dev/null; then
  if [ -f "$ROOTA_MNT/etc/init/ui.conf.disabled" ]; then
    mv -f "$ROOTA_MNT/etc/init/ui.conf.disabled" "$ROOTA_MNT/etc/init/ui.conf"
    say "re-enabled UI (ui.conf restored on eMMC ROOT-A)"
  elif [ -f "$ROOTA_MNT/etc/init/ui.conf" ]; then
    say "UI already enabled (ui.conf present)"
  else
    say "WARN: neither ui.conf nor ui.conf.disabled found on eMMC ROOT-A"
  fi
  { echo "--- eMMC ROOT-A /etc/init ui* ---"; ls -la "$ROOTA_MNT/etc/init/" | grep -i ui; } >> "$TRACE" 2>&1
  sync
  umount "$ROOTA_MNT" 2>/dev/null
else
  finish "FATAL: cannot mount eMMC ROOT-A $EROOTA" 20
fi

# 2. clean debug console from eMMC grub.cfg (keep quirk + flicker flags)
EMMC_ESP="$(partdev "$TARGET" 12)"
mkdir -p "$EESP_MNT"
if mount "$EMMC_ESP" "$EESP_MNT" 2>/dev/null; then
  G="$EESP_MNT/boot/grub/grub.cfg"
  if [ -f "$G" ]; then
    say "--- grub BEFORE ---"; grep '  linux' "$G" >> "$TRACE" 2>&1
    sed -i \
      -e 's/ console=tty1//; s/ earlycon=efifb//; s/ keep_bootcon//' \
      -e 's/loglevel=7/loglevel=4/' \
      "$G"
    say "--- grub AFTER ---"; grep '  linux' "$G" >> "$TRACE" 2>&1
    sync
  else
    say "WARN: eMMC grub.cfg missing at $G"
  fi
  umount "$EESP_MNT" 2>/dev/null
fi

finish "=== FINALIZE DONE — remove USB, boot eMMC (should reach OOBE) ===" 12
