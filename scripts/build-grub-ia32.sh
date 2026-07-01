#!/usr/bin/env bash
# build-grub-ia32.sh - build a small i386-efi GRUB core (bootia32.efi) that reads
# /boot/grub/grub.cfg from the ESP. Needs Debian grub-efi-ia32-bin.
# Small (~512K) vs grub-mkstandalone (~9M, too big for the 32M ChromeOS ESP).
set -euo pipefail
OUT=${1:-bootia32-core.efi}
grub-mkimage -O i386-efi -o "$OUT" -p /boot/grub \
  part_gpt fat search search_fs_file search_fs_uuid search_label \
  linux normal echo all_video efi_gop efi_uga configfile boot terminal \
  gfxterm gfxterm_background videotest video_bochs video_cirrus
echo "built $OUT ($(stat -c%s "$OUT") bytes)"; file "$OUT"
