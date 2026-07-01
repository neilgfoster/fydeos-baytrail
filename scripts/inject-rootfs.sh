#!/bin/sh
# inject-rootfs.sh - overlay firmware blobs / ALSA UCM / other files onto the
# FydeOS rootfs partition (ROOT-A) of an installer USB or an installed eMMC.
#
# Use for fixes that live on the rootfs rather than in the kernel: Wi-Fi/BT
# firmware (/lib/firmware/...), ALSA UCM audio profiles (/usr/share/alsa/...),
# etc. See docs/hardware-status.md for what belongs here vs. in the kernel.
#
# NOTE: modifying the rootfs breaks dm-verity, so this only works with the
# NON-verified boot menuentry (root=PARTUUID=..., which the injected grub.cfg
# uses). Do not use with a verified-boot entry.
#
# Layout: ChromeOS GPT -> ROOT-A is partition 3 (KERN-A=2, ROOT-A=3, ESP=12).
#
# Usage:
#   sudo sh inject-rootfs.sh --board <id> [--stage dir] [--dev /dev/sdX] [--slot A|B]
#
# With --board, defaults --stage to boards/<id>/stage/. The stage dir is a
# filesystem tree rooted at the rootfs root, e.g.:
#   stage/lib/firmware/brcm/brcmfmac43241b4-sdio.bin
#   stage/lib/firmware/brcm/brcmfmac43241b4-sdio.acer-w4-820.txt
#   stage/usr/share/alsa/ucm2/...
set -eu

HERE=$(CDPATH= cd "$(dirname "$0")/.." && pwd)
MNT=${MNT:-/tmp/iconia-root}
BOARD_ID="" ; STAGE="" ; DEV="" ; SLOT="A"

while [ $# -gt 0 ]; do
  case "$1" in
    --board) BOARD_ID=$2; shift 2 ;;
    --stage) STAGE=$2; shift 2 ;;
    --dev)   DEV=$2;   shift 2 ;;
    --slot)  SLOT=$2;  shift 2 ;;
    *) echo "unknown arg: $1" >&2; exit 2 ;;
  esac
done
[ -n "$STAGE" ] || { [ -n "$BOARD_ID" ] && STAGE="$HERE/boards/$BOARD_ID/stage"; }
[ -n "$STAGE" ] && [ -d "$STAGE" ] || { echo "ERROR: --stage <dir> (or --board) required" >&2; exit 2; }

# ROOT-A = partition 3, ROOT-B = partition 5
case "$SLOT" in A) PN=3 ;; B) PN=5 ;; *) echo "slot must be A or B" >&2; exit 2 ;; esac

part_for() { case "$1" in *[0-9]) echo "${1}p${PN}";; *) echo "${1}${PN}";; esac; }

find_root() {
  if [ -n "$DEV" ]; then part_for "$DEV"; return; fi
  # identify the installer disk the same way as the other scripts: its p12 ESP
  # holds /syslinux/vmlinuz.A. Then take partition $PN of that same disk.
  for d in /dev/sd? /dev/mmcblk? /dev/nvme?n?; do
    [ -b "$d" ] || continue
    case "$d" in *[0-9]) esp="${d}p12";; *) esp="${d}12";; esac
    [ -b "$esp" ] || continue
    if mount -o ro "$esp" "$MNT" 2>/dev/null; then
      if [ -f "$MNT/syslinux/vmlinuz.A" ]; then umount "$MNT"; part_for "$d"; return; fi
      umount "$MNT" 2>/dev/null || true
    fi
  done
  return 1
}

mkdir -p "$MNT"
ROOT=$(find_root) || { echo "ERROR: could not find ROOT-$SLOT; pass --dev /dev/sdX" >&2; exit 1; }
echo "ROOT-$SLOT: $ROOT"
mount "$ROOT" "$MNT"
trap 'sync; umount "$MNT" 2>/dev/null || true' EXIT

echo "=== files to overlay ==="
( cd "$STAGE" && find . -type f | sed 's|^\.||' )

# copy preserving tree; back up anything we overwrite into .iconia-backup/
BK="$MNT/.iconia-backup"
( cd "$STAGE" && find . -type f | while read -r f; do
    rel=${f#./}
    if [ -e "$MNT/$rel" ]; then mkdir -p "$BK/$(dirname "$rel")"; cp -an "$MNT/$rel" "$BK/$rel" 2>/dev/null || true; fi
    mkdir -p "$MNT/$(dirname "$rel")"
    cp -a "$STAGE/$rel" "$MNT/$rel"
  done )

echo "done. Overwritten originals backed up under ROOT-$SLOT:/.iconia-backup/"
echo "Remember: boot the NON-verified menuentry (verity is now invalid)."
