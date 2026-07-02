#!/bin/sh
# Iconia W4-820 — one-shot eMMC auto-install (keyboard-free).
#
# Runs ON THE TABLET (booted from the USB) via the upstart job
# iconia-install.conf, but ONLY when the boot cmdline contains
# `iconia_install=1`. It:
#   1. installs FydeOS to the eMMC  (chromeos-install --dst /dev/mmcblk0 --yes)
#   2. re-injects our 32-bit-UEFI boot chain onto the eMMC ESP
#      (0x3f vmlinuz + bootia32.efi + production grub.cfg, root=PARTUUID fixed
#      to the freshly-created eMMC ROOT-A)
#   3. logs everything to the USB ESP (FAT — readable back on the build host)
#   4. drops a sentinel so it NEVER runs twice, then powers off.
#
# The rootfs (eMMC ROOT-A) is a bitwise copy of the USB ROOT-A, so our injected
# modules + cleared ro-compat byte come along automatically — nothing to do there.
set -u
export PATH=/usr/sbin:/usr/bin:/sbin:/bin

TARGET=/dev/mmcblk0
UESP_MNT=/mnt/iconia-uesp
EESP_MNT=/mnt/iconia-eesp

partdev() {  # partdev <disk> <partnum> -> mmcblk0 -> mmcblk0p3 ; sda -> sda3
  case "$1" in
    *[0-9]) echo "$1p$2" ;;
    *)      echo "$1$2"  ;;
  esac
}

# --- locate the USB (our boot disk) and its ESP (partition 12) ---
USB_DISK="$(rootdev -s -d)"
USB_ESP="$(partdev "$USB_DISK" 12)"

mkdir -p "$UESP_MNT" "$EESP_MNT"
mount "$USB_ESP" "$UESP_MNT" || { echo "FATAL: cannot mount USB ESP $USB_ESP"; exit 1; }

LOG="$UESP_MNT/iconia-install.log"
SENTINEL="$UESP_MNT/iconia-install.done"
log() { echo "[$(date -u '+%Y-%m-%dT%H:%M:%SZ')] $*" | tee -a "$LOG"; }

if [ -e "$SENTINEL" ]; then
  log "sentinel present — install already ran; skipping."
  umount "$UESP_MNT" 2>/dev/null
  exit 0
fi

log "=== iconia eMMC auto-install START ==="
log "USB_DISK=$USB_DISK  USB_ESP=$USB_ESP  TARGET=$TARGET"
{ echo "--- lsblk ---"; lsblk; } >> "$LOG" 2>&1 || true

# --- 1. install FydeOS to the eMMC (non-interactive) ---
log "running: chromeos-install --dst $TARGET --yes"
if chromeos-install --dst "$TARGET" --yes >> "$LOG" 2>&1; then
  log "chromeos-install SUCCESS"
else
  rc=$?
  log "chromeos-install FAILED rc=$rc — eMMC left as-is, NO sentinel (safe to retry)"
  umount "$UESP_MNT" 2>/dev/null
  exit "$rc"
fi

# --- 2. read the freshly-created eMMC ROOT-A PARTUUID ---
EMMC_ROOTA="$(partdev "$TARGET" 3)"
ROOT_PARTUUID="$(cgpt show -i 3 -u "$TARGET" 2>/dev/null)"
log "eMMC ROOT-A=$EMMC_ROOTA  PARTUUID=$ROOT_PARTUUID"
if [ -z "$ROOT_PARTUUID" ]; then
  log "ERROR: could not read eMMC ROOT-A PARTUUID — aborting before ESP fix (NO sentinel)"
  umount "$UESP_MNT" 2>/dev/null
  exit 1
fi

# --- 3. overwrite the eMMC ESP with our 32-bit-UEFI boot chain ---
EMMC_ESP="$(partdev "$TARGET" 12)"
mount "$EMMC_ESP" "$EESP_MNT" || { log "FATAL: cannot mount eMMC ESP $EMMC_ESP"; umount "$UESP_MNT"; exit 1; }
mkdir -p "$EESP_MNT/syslinux" "$EESP_MNT/efi/boot" "$EESP_MNT/boot/grub"

cp -f "$UESP_MNT/syslinux/vmlinuz.A"    "$EESP_MNT/syslinux/vmlinuz.A"
cp -f "$UESP_MNT/efi/boot/bootia32.efi" "$EESP_MNT/efi/boot/bootia32.efi"
cp -f "$UESP_MNT/efi/boot/bootx64.efi"  "$EESP_MNT/efi/boot/bootx64.efi" 2>/dev/null || true

cat > "$EESP_MNT/boot/grub/grub.cfg" <<EOF
set timeout=2
set default=0
insmod part_gpt
insmod fat
insmod ext2
insmod linux
insmod all_video
insmod search_fs_file
search --no-floppy --file --set=root /syslinux/vmlinuz.A
menuentry "FydeOS A (W4-820 eMMC)" {
  linux /syslinux/vmlinuz.A init=/sbin/init rootwait ro noresume loglevel=4 noinitrd audit=0 cros_efi i915.enable_psr=0 i915.enable_fbc=0 i915.enable_dc=0 root=PARTUUID=$ROOT_PARTUUID
  boot
}
EOF

# --- 4. verify the eMMC kernel carries the 32-bit EFI handover bit ---
# xloadflags is 2 bytes at offset 0x236 (566). Low byte must have 0x04 set
# (our build reads 3f). od prints low byte first, e.g. "3f 00".
XLF="$(od -An -tx1 -j 566 -N2 "$EESP_MNT/syslinux/vmlinuz.A" | tr -s ' ')"
log "eMMC vmlinuz.A xloadflags bytes=[$XLF] (want low byte 0x04 set, e.g. '3f 00')"

sync
{ echo "--- eMMC ESP tree ---"; ls -laR "$EESP_MNT"; } >> "$LOG" 2>&1
umount "$EESP_MNT" 2>/dev/null

# --- 5. done: sentinel + power off so we can review before the first eMMC boot ---
: > "$SENTINEL"
log "=== iconia eMMC auto-install COMPLETE — powering off (remove USB, then boot eMMC) ==="
sync
umount "$UESP_MNT" 2>/dev/null
sleep 2
poweroff -f 2>/dev/null || poweroff || shutdown -P now || halt -p
