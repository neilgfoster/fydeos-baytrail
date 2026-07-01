#!/bin/sh
# inject-kernel.sh - put a custom kernel + 32-bit GRUB onto a FydeOS installer USB.
#
# Run on the FydeOS/ChromeOS host (crosh -> `shell`) with the installer USB
# plugged in. Backs up the original vmlinuz, installs the rebuilt one, and ensures
# bootia32.efi + a gptpriority-free /boot/grub/grub.cfg are present so 32-bit UEFI
# firmware can boot the chain.
#
# Usage:
#   sudo sh inject-kernel.sh --board <id> [--kernel vmlinuz] [--dev /dev/sdX] [--slot A|B]
#
# With --board, defaults --kernel to boards/<id>/out/vmlinuz and reads BOOTIA32_URL
# from boards/<id>/board.env. ESP is auto-detected like inspect-usb.sh (partition 12).
set -eu

HERE=$(CDPATH= cd "$(dirname "$0")/.." && pwd)
MNT=${MNT:-/tmp/iconia-esp}
BOARD_ID="" ; KERNEL="" ; DEV="" ; SLOT="A"

while [ $# -gt 0 ]; do
  case "$1" in
    --board)  BOARD_ID=$2; shift 2 ;;
    --kernel) KERNEL=$2; shift 2 ;;
    --dev)    DEV=$2;    shift 2 ;;
    --slot)   SLOT=$2;   shift 2 ;;
    *) echo "unknown arg: $1" >&2; exit 2 ;;
  esac
done
if [ -n "$BOARD_ID" ]; then
  BD="$HERE/boards/$BOARD_ID"
  [ -f "$BD/board.env" ] && . "$BD/board.env"
  [ -n "$KERNEL" ] || KERNEL="$BD/out/vmlinuz"
fi
BOOTIA32_URL=${BOOTIA32_URL:-https://github.com/hirotakaster/baytail-bootia32.efi/raw/master/bootia32.efi}
[ -n "$KERNEL" ] && [ -f "$KERNEL" ] || { echo "ERROR: kernel not found ($KERNEL); pass --kernel <file> or build first" >&2; exit 2; }

find_p12() {
  if [ -n "$DEV" ]; then case "$DEV" in *[0-9]) echo "${DEV}p12";; *) echo "${DEV}12";; esac; return; fi
  for d in /dev/sd? /dev/mmcblk? /dev/nvme?n?; do
    [ -b "$d" ] || continue
    case "$d" in *[0-9]) p="${d}p12";; *) p="${d}12";; esac
    [ -b "$p" ] || continue
    if mount -o ro "$p" "$MNT" 2>/dev/null; then
      if [ -f "$MNT/syslinux/vmlinuz.A" ]; then umount "$MNT"; echo "$p"; return; fi
      umount "$MNT" 2>/dev/null || true
    fi
  done
  return 1
}

mkdir -p "$MNT"
ESP=$(find_p12) || { echo "ERROR: installer ESP not found; pass --dev /dev/sdX" >&2; exit 1; }
echo "ESP: $ESP"
mount "$ESP" "$MNT"
trap 'sync; umount "$MNT" 2>/dev/null || true' EXIT

# 1. back up + replace kernel
TS=$(date +%Y%m%d-%H%M%S)
ORIG="$MNT/syslinux/vmlinuz.$SLOT"
if [ -f "$ORIG" ] && [ ! -f "$ORIG.orig" ]; then
  cp -a "$ORIG" "$ORIG.orig"
  echo "backed up original -> vmlinuz.$SLOT.orig"
fi
cp -f "$KERNEL" "$ORIG"
echo "installed custom kernel -> vmlinuz.$SLOT"

# verify the handover bit on what we just wrote
XLF=$(dd if="$ORIG" bs=1 skip=566 count=1 2>/dev/null | od -An -tu1 | tr -d ' \n')
if [ $(( XLF & 4 )) -ne 0 ]; then
  echo "OK: XLF_EFI_HANDOVER_32 is SET (xloadflags=0x$(printf '%02x' "$XLF")) - bootable on 32-bit UEFI"
else
  echo "WARNING: XLF_EFI_HANDOVER_32 is CLEAR (xloadflags=0x$(printf '%02x' "$XLF")) - this kernel will NOT boot on 32-bit UEFI"
fi

# 2. ensure 32-bit GRUB
if [ ! -f "$MNT/efi/boot/bootia32.efi" ]; then
  echo "fetching bootia32.efi ..."
  curl -fL -o "$MNT/efi/boot/bootia32.efi" "$BOOTIA32_URL"
fi

# 3. ensure gptpriority-free grub.cfg at the prefix the prebuilt GRUB searches
PU=$(grep -o 'PARTUUID=[0-9A-Fa-f-]*' "$MNT/efi/boot/grub.cfg" 2>/dev/null | head -n1 | sed 's/PARTUUID=//')
mkdir -p "$MNT/boot/grub"
cat > "$MNT/boot/grub/grub.cfg" <<EOF
set timeout=10
set default=0
insmod part_gpt
insmod fat
insmod linux
insmod all_video
insmod search_fs_file
search --no-floppy --file --set=root /syslinux/vmlinuz.$SLOT
menuentry "FydeOS image $SLOT (32-bit UEFI, custom kernel)" {
  linux /syslinux/vmlinuz.$SLOT init=/sbin/init rootwait ro noresume loglevel=7 noinitrd audit=0 console= i915.modeset=1 cros_efi root=PARTUUID=${PU:-CHANGE-ME}
}
EOF
echo "wrote /boot/grub/grub.cfg (root=PARTUUID=${PU:-CHANGE-ME})"

echo "done. sync + unmount on exit; safe to remove USB afterwards."
