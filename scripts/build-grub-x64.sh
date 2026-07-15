#!/usr/bin/env bash
# build-grub-x64.sh - build a small x86_64-efi GRUB core (grubx64.efi) that reads
# grub.cfg from a prefix directory on the ESP it was booted from. Needs Debian
# grub-efi-amd64-bin. Mirrors build-grub-ia32.sh's approach (same grub-mkimage -p
# <prefix> convention, already proven on boards/iconia-w4-820), but the prefix is a
# parameter here rather than hardcoded to /boot/grub: on a shared ESP that already has
# an OS installed (e.g. ThinkPad10's Windows dual-boot), /boot/grub can collide
# case-insensitively with an existing Windows \BOOT\ directory (confirmed live on the
# ThinkPad10 eMMC ESP, T10) - pick a prefix confirmed free on the target ESP instead.
set -euo pipefail
OUT=${1:-grubx64-core.efi}
PREFIX=${2:-/boot/grub}
grub-mkimage -O x86_64-efi -o "$OUT" -p "$PREFIX" \
  part_gpt fat search search_fs_file search_fs_uuid search_label \
  linux normal echo all_video efi_gop configfile boot terminal \
  gfxterm gfxterm_background videotest video_bochs video_cirrus
echo "built $OUT ($(stat -c%s "$OUT") bytes)"; file "$OUT"
