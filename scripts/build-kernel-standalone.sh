#!/usr/bin/env bash
# build-kernel-standalone.sh - build a ChromeOS/openFyde kernel vmlinuz with
# CONFIG_EFI_MIXED, WITHOUT the full cros_sdk / 94G repo sync.
#
# This is the lean path (Option A): clone just the kernel git (~1.8G) and build
# arch/x86/boot/bzImage with plain `make` using ChromeOS's own config machinery.
# Proven on the Iconia W4-820 (kernel 6.6.76, gcc, no clang needed).
#
# Prereqs (Debian/Ubuntu): build-essential bc bison flex libssl-dev libelf-dev cpio kmod rsync
#
# Usage:
#   scripts/build-kernel-standalone.sh --board <id> [clone|config|build|all]
set -euo pipefail

HERE=$(cd "$(dirname "$0")/.." && pwd)
BOARD_ID="" ; ACTION="all"
while [ $# -gt 0 ]; do
  case "$1" in
    --board) BOARD_ID=$2; shift 2 ;;
    clone|config|build|all) ACTION=$1; shift ;;
    *) echo "usage: $0 --board <id> [clone|config|build|all]"; exit 2 ;;
  esac
done
[ -n "$BOARD_ID" ] || { echo "ERROR: --board <id> required"; exit 2; }
BD="$HERE/boards/$BOARD_ID"
# shellcheck disable=SC1091
. "$BD/board.env"
[ "${CPU_64BIT:-yes}" = yes ] || { echo "ERROR: $BOARD_ID CPU is 32-bit; unsupported"; exit 1; }

SRC=${KERNEL_SRC:-$HOME/openfyde/kernel-6.6}
JOBS=$(nproc)

deps(){ for t in make gcc bc bison flex cpio; do command -v "$t" >/dev/null || { echo "MISSING toolchain: $t (apt install build-essential bc bison flex libssl-dev libelf-dev cpio kmod rsync)"; exit 1; }; done; }

cmd_clone(){
  [ -d "$SRC/.git" ] && { echo "already cloned at $SRC"; return; }
  git clone --depth 1 --single-branch -b "$KERNEL_BRANCH" "$KERNEL_GIT" "$SRC"
  ( cd "$SRC" && make kernelversion )
}

cmd_config(){
  cd "$SRC"
  CHROMEOS_KERNEL_FAMILY="${KERNEL_FAMILY:-chromeos}" chromeos/scripts/prepareconfig "$KERNEL_FLAVOUR"
  { echo "# --- baytrail shared efi-mixed ---"; cat "$HERE/config/efi-mixed.config"; } >> .config
  for f in "$BD"/config/*.config; do [ -e "$f" ] && { echo "# board $BOARD_ID $(basename "$f")"; cat "$f"; } >> .config; done
  # optional: match module dir name to reduce mismatch (still differs by sublevel)
  [ -n "${KERNEL_LOCALVERSION:-}" ] && echo "CONFIG_LOCALVERSION=\"$KERNEL_LOCALVERSION\"" >> .config
  make olddefconfig
  echo "=== EFI handover config ==="; grep -E 'CONFIG_EFI_MIXED|CONFIG_EFI_HANDOVER_PROTOCOL|CONFIG_EFI_STUB' .config
}

cmd_build(){
  deps; cd "$SRC"
  make -j"$JOBS" bzImage
  mkdir -p "$BD/out"; cp -f arch/x86/boot/bzImage "$BD/out/vmlinuz"
  local xlf; xlf=$(od -An -tu1 -j 566 -N1 "$BD/out/vmlinuz" | tr -d ' ')
  printf 'built -> boards/%s/out/vmlinuz  xloadflags.lo=0x%02x  HANDOVER32=%s\n' \
    "$BOARD_ID" "$xlf" "$([ $((xlf & 4)) -ne 0 ] && echo YES || echo NO)"
  [ $((xlf & 4)) -ne 0 ] || { echo "WARNING: handover bit NOT set - would not boot on 32-bit UEFI"; exit 1; }
}

case "$ACTION" in
  clone) cmd_clone ;;
  config) cmd_config ;;
  build) cmd_build ;;
  all) cmd_clone; cmd_config; cmd_build ;;
esac
