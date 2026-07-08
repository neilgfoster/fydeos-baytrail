#!/bin/sh
# Iconia W4-820 — EMERGENCY recovery from bootloop (PID 1, run from USB utility boot).
#
# Session 11 kernel #12 (rotation-fix SSDT + built-in initramfs) bootloops on the
# eMMC. The eMMC ESP already has a known-good backup sitting right next to the
# broken vmlinuz.A (vmlinuz.A.bak-bt, the working Bluetooth-era kernel from
# session 8) — this script just restores it, no data needed from USB at all.
export PATH=/usr/sbin:/usr/bin:/sbin:/bin
CON=/dev/tty1
EESP_MNT=/mnt/iconia-eesp
# Log directly onto the eMMC ESP itself (small text file, always has room) so a
# failure is actually readable afterward — previously this only logged to the
# ephemeral USB rootfs, which vanishes on poweroff, leaving zero evidence.
TRACE=/mnt/iconia-eesp/syslinux/iconia-esp-restore.log

mount -t proc proc /proc 2>/dev/null
mount -t sysfs sys /sys 2>/dev/null
mount -t devtmpfs dev /dev 2>/dev/null
mount -t tmpfs run /run 2>/dev/null

say() { _m="[$(date -u '+%H:%M:%S' 2>/dev/null)] $*"; echo "ICONIA $_m" > "$CON" 2>/dev/null||true; echo "$_m" >> "$TRACE" 2>/dev/null||true; echo "ICONIA: $*" > /dev/kmsg 2>/dev/null||true; sync 2>/dev/null||true; }
# Halt with message on screen instead of racing to power off — unreadable
# scrolling + fast poweroff is why the last two runs left us blind.
finish() { echo "" > "$CON"; echo "#### ICONIA RESTORE — HALT ####" > "$CON"; say "$1"; say "=== read this, then hold power ~10s to shut down ==="; while true; do sleep 3600; done; }
partdev() { case "$1" in *[0-9]) echo "$1p$2";; *) echo "$1$2";; esac; }
find_emmc() { for d in /sys/block/mmcblk*; do b=$(basename "$d"); case "$b" in *boot*|*rpmb*) continue;; esac; sz=$(cat "$d/size" 2>/dev/null); [ "${sz:-0}" -gt 100000000 ] && { echo "/dev/$b"; return 0; }; done; return 1; }

n=0; while [ "$n" -lt 6 ]; do echo "" > "$CON"; echo "#### ICONIA ESP RESTORE (bootloop recovery) ####" > "$CON"; n=$((n+1)); done
say "=== iconia-esp-restore.sh PID $$ ==="

mkdir -p /run/udev; udevd --daemon 2>/dev/null || /lib/systemd/systemd-udevd --daemon 2>/dev/null
udevadm trigger --action=add 2>/dev/null; udevadm settle --timeout=10 2>/dev/null

DRV=/sys/bus/platform/drivers/sdhci-acpi; i=0; TARGET="$(find_emmc)"
while [ -z "$TARGET" ] && [ "$i" -lt 40 ]; do
  for base in 80860F14:00 80860F14:01; do [ -e "/sys/bus/platform/devices/$base" ] || continue; echo "$base" > "$DRV/unbind" 2>/dev/null; echo "$base" > "$DRV/bind" 2>/dev/null; done
  udevadm trigger --action=add 2>/dev/null; udevadm settle --timeout=5 2>/dev/null; sleep 2; i=$((i+1)); TARGET="$(find_emmc)"; say "ensure eMMC try $i: ${TARGET:-absent}"
done
[ -n "$TARGET" ] || finish "FATAL: no eMMC after $i tries — power-cycle & retry" 20
say "eMMC = $TARGET"

mkdir -p "$EESP_MNT"
mount -o rw "$(partdev "$TARGET" 12)" "$EESP_MNT" 2>/dev/null || finish "FATAL: cannot mount eMMC ESP" 20
say "=== iconia-esp-restore.sh PID $$ === eMMC=$TARGET"
say "free space: $(df -h "$EESP_MNT" 2>&1 | awk 'END{print $4}')"

# Known-good session-8 kernel hash — the copy is only trusted if it matches this.
GOOD=73733cc986f817de9bfa06058e6160e7cadb69ca46d4826e27641479a48db96a

cd "$EESP_MNT/syslinux" || finish "FATAL: no syslinux dir on eMMC ESP" 20
[ -f vmlinuz.A.bak-bt ] || finish "FATAL: vmlinuz.A.bak-bt not found — cannot auto-recover" 20

say "before: $(sha256sum vmlinuz.A 2>&1)"
say "free BEFORE: $(df -h . 2>&1 | awk 'END{print $4}')"

# ROOT CAUSE of the earlier failed restores: the ESP is nearly full (~4.5MB free)
# so cp -f bak-bt over vmlinuz.A ran OUT OF SPACE and left a TRUNCATED (corrupt)
# kernel (5120 bytes short) that freezes at boot. Fix: free real space FIRST by
# deleting dead weight (the aborted rotation kernel #12 backup + the old bad
# vmlinuz.A itself), THEN copy, THEN verify the hash before declaring success.
say "removing dead weight to free ESP space ..."
rm -f vmlinuz.A.bad-12 vmlinuz.A.bad-* 2>/dev/null
rm -f vmlinuz.A 2>/dev/null
sync
say "free AFTER cleanup: $(df -h . 2>&1 | awk 'END{print $4}')"

say "restoring vmlinuz.A.bak-bt -> vmlinuz.A (undoing bad kernel #12)"
cp -f vmlinuz.A.bak-bt vmlinuz.A
RC=$?
sync
say "cp exit code: $RC"

NEW="$(sha256sum vmlinuz.A 2>&1 | awk '{print $1}')"
say "after: $NEW"
sync

# --- session-16: also undo the R144 A/B-test grub changes (default=1 -> vmlinuz.r144
#     bootloops). Our vmlinuz.A itself was fine this time; the fault was grub. ---
GRUB="$EESP_MNT/boot/grub/grub.cfg"
if [ -f "$EESP_MNT/boot/grub/grub.cfg.pre-r144.bak" ]; then
  say "restoring grub.cfg from pre-r144 backup (single #14 entry, default=0)"
  cp -f "$EESP_MNT/boot/grub/grub.cfg.pre-r144.bak" "$GRUB"
elif [ -f "$GRUB" ]; then
  say "no pre-r144 backup found; forcing grub default=0"
  sed -i "s/^set default=.*/set default=0/" "$GRUB"
fi
rm -f "$EESP_MNT/syslinux/vmlinuz.r144" 2>/dev/null
sync
say "grub default now: $(grep -E '^set default=' "$GRUB" 2>&1)"

umount "$EESP_MNT" 2>/dev/null

if [ "$NEW" = "$GOOD" ]; then
  finish "*** RESTORE VERIFIED OK (hash matches good kernel) — remove USB, boot eMMC ***" 12
else
  finish "!!! RESTORE FAILED — vmlinuz.A hash $NEW != good $GOOD — DO NOT boot eMMC, tell me this line !!!" 12
fi
