#!/bin/sh
# Iconia W4-820 — one-shot eMMC auto-install (keyboard-free).
#
# Runs ON THE TABLET (booted from the USB), launched DETACHED by the upstart job
# iconia-install.conf, but ONLY when the boot cmdline contains `iconia_install=1`.
#
# OBSERVABILITY: the tablet has no serial port and we can't keep persistent logs
# across a hard power-off, so this prints EVERYTHING live to the text console
# (/dev/tty1) — the UI is disabled on this USB so tty1 stays visible. We also
# mirror to /dev/kmsg and to a trace file on ROOT-A (best-effort backup).
#
# Steps: install FydeOS to eMMC -> re-inject our 0x3f kernel + bootia32.efi +
# grub.cfg (fixed PARTUUID) onto the eMMC ESP -> sentinel -> power off.
# eMMC ROOT-A is a bitwise copy of USB ROOT-A, so our modules come along.
set -u
export PATH=/usr/sbin:/usr/bin:/sbin:/bin

TARGET=/dev/mmcblk0
UESP_MNT=/mnt/iconia-uesp
EESP_MNT=/mnt/iconia-eesp
CON=/dev/tty1
TRACE=/iconia-trace.log

# make ROOT-A writable so the trace file persists (readable offline on build host)
mount -o remount,rw / 2>/dev/null || true

emit() {
  _m="[$(date -u '+%H:%M:%S')] $*"
  echo "ICONIA $_m"  > "$CON"       2>/dev/null || true
  echo "$_m"        >> "$TRACE"     2>/dev/null || true
  echo "ICONIA: $*"  > /dev/kmsg    2>/dev/null || true
  sync
}

emit "=== iconia-install.sh STARTED (pid $$) ==="

partdev() {  # mmcblk0 -> mmcblk0p3 ; sda -> sda3
  case "$1" in
    *[0-9]) echo "$1p$2" ;;
    *)      echo "$1$2"  ;;
  esac
}

USB_DISK="$(rootdev -s -d)"
USB_ESP="$(partdev "$USB_DISK" 12)"
emit "USB_DISK=$USB_DISK  USB_ESP=$USB_ESP  TARGET=$TARGET"

mkdir -p "$UESP_MNT" "$EESP_MNT"
if mount "$USB_ESP" "$UESP_MNT" 2>/dev/null; then
  emit "mounted USB ESP at $UESP_MNT"
  SENTINEL="$UESP_MNT/iconia-install.done"
  if [ -e "$SENTINEL" ]; then
    emit "sentinel present — already ran; skipping."
    umount "$UESP_MNT" 2>/dev/null
    exit 0
  fi
else
  emit "WARN: could not mount USB ESP $USB_ESP — continuing (will remount for copy step)"
  SENTINEL=""
fi

emit "--- lsblk ---"
lsblk > "$CON" 2>/dev/null || true

# --- 1. install FydeOS to the eMMC (non-interactive), output live to console ---
emit "running: chromeos-install --dst $TARGET --yes  (this is the slow step)"
{ chromeos-install --dst "$TARGET" --yes; echo "$?" > /tmp/ic_rc; } 2>&1 | tee -a "$TRACE" > "$CON"
rc="$(cat /tmp/ic_rc 2>/dev/null || echo 1)"
sync
if [ "$rc" = "0" ]; then
  emit "chromeos-install SUCCESS"
else
  emit "chromeos-install FAILED rc=$rc — eMMC left as-is, NO sentinel (safe to retry)"
  exit "$rc"
fi

# --- 2. eMMC ROOT-A PARTUUID ---
ROOT_PARTUUID="$(cgpt show -i 3 -u "$TARGET" 2>/dev/null)"
emit "eMMC ROOT-A PARTUUID=$ROOT_PARTUUID"
[ -n "$ROOT_PARTUUID" ] || { emit "ERROR: no eMMC ROOT-A PARTUUID — abort before ESP fix"; exit 1; }

# make sure the USB ESP is mounted (need our vmlinuz/bootia32 source)
mountpoint -q "$UESP_MNT" 2>/dev/null || mount "$(partdev "$(rootdev -s -d)" 12)" "$UESP_MNT" 2>/dev/null
SENTINEL="$UESP_MNT/iconia-install.done"

# --- 3. overwrite eMMC ESP with our 32-bit-UEFI boot chain ---
EMMC_ESP="$(partdev "$TARGET" 12)"
mount "$EMMC_ESP" "$EESP_MNT" || { emit "FATAL: cannot mount eMMC ESP $EMMC_ESP"; exit 1; }
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

XLF="$(od -An -tx1 -j 566 -N2 "$EESP_MNT/syslinux/vmlinuz.A" | tr -s ' ')"
emit "eMMC vmlinuz.A xloadflags=[$XLF] (want low byte 0x04 set, e.g. '3f 00')"
sync
umount "$EESP_MNT" 2>/dev/null

# --- 4. done ---
[ -n "$SENTINEL" ] && : > "$SENTINEL"
emit "=== COMPLETE — powering off in 10s (remove USB, then boot eMMC) ==="
sync
umount "$UESP_MNT" 2>/dev/null
sleep 10
poweroff -f 2>/dev/null || poweroff || shutdown -P now || halt -p
