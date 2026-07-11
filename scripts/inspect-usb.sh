#!/bin/sh
# inspect-usb.sh - profile a FydeOS/openFyde installer USB.
#
# Run on the FydeOS/ChromeOS host (crosh -> `shell`) with the installer USB
# plugged in. Mounts the EFI System Partition (ESP) read-only and reports the
# kernel version, xloadflags (32-bit EFI handover bit), kernel command lines and
# PARTUUIDs. Writes a machine-readable profile to ./usb-profile.env.
#
# Usage:
#   sudo sh inspect-usb.sh [--board <id>] [/dev/sdX]   # device optional; auto-detected
#
# With --board, writes boards/<id>/usb-profile.env; otherwise ./usb-profile.env.
# POSIX sh only (busybox-safe): uses od, dd, tr, grep, sed.
set -eu

HERE=$(CDPATH= cd "$(dirname "$0")/.." && pwd)
MNT=${MNT:-/tmp/baytrail-esp}
BOARD_ID="" ; DEV=""
while [ $# -gt 0 ]; do
  case "$1" in
    --board) BOARD_ID=$2; shift 2 ;;
    *) DEV=$1; shift ;;
  esac
done
if [ -n "$BOARD_ID" ]; then
  mkdir -p "$HERE/boards/$BOARD_ID"
  OUT="$HERE/boards/$BOARD_ID/usb-profile.env"
else
  OUT=${OUT:-./usb-profile.env}
fi

log() { printf '%s\n' "$*" >&2; }

# --- locate the installer's ESP -------------------------------------------------
# The ChromeOS layout has 12 partitions; partition 12 is the 32M FAT ESP that
# holds /syslinux/vmlinuz.A. Probe candidate whole disks for that signature.
find_esp() {
  if [ -n "$DEV" ]; then
    echo "${DEV}12"; return 0
  fi
  for d in /dev/sd? /dev/mmcblk? /dev/nvme?n?; do
    [ -b "$d" ] || continue
    # partition 12 naming differs: sdb12 vs mmcblk0p12 vs nvme0n1p12
    case "$d" in
      *[0-9]) p="${d}p12" ;;
      *)      p="${d}12"  ;;
    esac
    [ -b "$p" ] || continue
    if mount -o ro "$p" "$MNT" 2>/dev/null; then
      if [ -f "$MNT/syslinux/vmlinuz.A" ]; then
        umount "$MNT" 2>/dev/null || true
        echo "$p"; return 0
      fi
      umount "$MNT" 2>/dev/null || true
    fi
  done
  return 1
}

# read a little-endian N-byte integer at OFFSET of FILE
le_int() { # file offset nbytes
  dd if="$1" bs=1 skip="$2" count="$3" 2>/dev/null \
    | od -An -tu"$3" | tr -d ' \n'
}

# read a NUL-terminated string at OFFSET of FILE
cstr() { # file offset [max]
  dd if="$1" bs=1 skip="$2" count="${3:-256}" 2>/dev/null \
    | LC_ALL=C tr '\000' '\n' | head -n1
}

mkdir -p "$MNT"
ESP=$(find_esp) || { log "ERROR: could not find a FydeOS installer ESP. Pass the device explicitly, e.g. sudo sh inspect-usb.sh /dev/sdb"; exit 1; }
log "ESP: $ESP"

mount -o ro "$ESP" "$MNT"
trap 'umount "$MNT" 2>/dev/null || true' EXIT

: > "$OUT"
emit() { printf '%s=%s\n' "$1" "$2" >>"$OUT"; }
emit ESP_DEVICE "$ESP"

for K in A B; do
  V="$MNT/syslinux/vmlinuz.$K"
  [ -f "$V" ] || continue

  # xloadflags: 2 bytes at 0x236. bit 0x04 = XLF_EFI_HANDOVER_32.
  XLF_LO=$(le_int "$V" 566 1)   # 0x236
  HANDOVER32=no
  [ $(( XLF_LO & 4 )) -ne 0 ] && HANDOVER32=yes

  # kernel version: 2-byte LE pointer at 0x20E (526), string at (ptr + 0x200).
  VP=$(le_int "$V" 526 2)
  VOFF=$(( VP + 512 ))
  KVER=$(cstr "$V" "$VOFF" 128)

  log "vmlinuz.$K: version='$KVER'  xloadflags=0x$(printf '%02x' "$XLF_LO")  HANDOVER32=$HANDOVER32"
  emit "KVER_$K"        "\"$KVER\""
  emit "XLOADFLAGS_$K"  "$(printf '0x%02x' "$XLF_LO")"
  emit "HANDOVER32_$K"  "$HANDOVER32"
done

# kernel command lines + PARTUUIDs from grub.cfg
if [ -f "$MNT/efi/boot/grub.cfg" ]; then
  log "--- grub.cfg linux entries ---"
  grep -n 'linux ' "$MNT/efi/boot/grub.cfg" >&2 || true
  PU=$(grep -o 'PARTUUID=[0-9A-Fa-f-]*' "$MNT/efi/boot/grub.cfg" | sort -u | tr '\n' ' ')
  emit PARTUUIDS "\"$PU\""
  log "PARTUUIDs: $PU"
fi

# is a 32-bit GRUB already present?
BIA32=no; [ -f "$MNT/efi/boot/bootia32.efi" ] && BIA32=yes
emit BOOTIA32_PRESENT "$BIA32"

log ""
log "Wrote profile -> $OUT"
log "Next: build a kernel with CONFIG_EFI_MIXED (scripts/build-kernel.sh),"
log "then inject it (scripts/inject-kernel.sh)."
