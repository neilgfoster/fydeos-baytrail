#!/usr/bin/env bash
# build-kernel.sh - build an openFyde kernel with the 32-bit EFI handover entry
# (CONFIG_EFI_MIXED) so it boots on 32-bit UEFI firmware. Board-aware: all the
# device-specific pins live in boards/<board>/board.env.
#
# Run in a beefy x86_64 Linux env (a FydeOS Crostini container works: ~120 GB
# free disk + 16 GB RAM + several hours for the first sync/build).
#
# Usage:
#   scripts/build-kernel.sh --board <id> sync     # repo init + sync (slow, one-time)
#   scripts/build-kernel.sh --board <id> config   # apply efi-mixed + board fragments/patches
#   scripts/build-kernel.sh --board <id> build    # print the in-SDK emerge commands
#   scripts/build-kernel.sh --board <id> extract  # copy vmlinuz to boards/<id>/out/
#   scripts/build-kernel.sh --board <id> all
set -euo pipefail

HERE=$(cd "$(dirname "$0")/.." && pwd)
BOARD_ID="" ; ACTION=""
while [ $# -gt 0 ]; do
  case "$1" in
    --board) BOARD_ID=$2; shift 2 ;;
    sync|config|build|extract|all) ACTION=$1; shift ;;
    *) echo "usage: $0 --board <id> {sync|config|build|extract|all}"; exit 2 ;;
  esac
done
[ -n "$BOARD_ID" ] || { echo "ERROR: --board <id> required (see boards/)"; exit 2; }
BOARD_DIR="$HERE/boards/$BOARD_ID"
[ -f "$BOARD_DIR/board.env" ] || { echo "ERROR: no board.env at $BOARD_DIR"; exit 2; }
# shellcheck disable=SC1091
. "$BOARD_DIR/board.env"

# refuse boards that can't possibly work
if [ "${CPU_64BIT:-yes}" != "yes" ]; then
  echo "ERROR: $BOARD_ID has CPU_64BIT=$CPU_64BIT; a 64-bit FydeOS kernel cannot run on a 32-bit CPU."; exit 1
fi

ROOT=${OPENFYDE_ROOT:-$HOME/openfyde}      # ONE shared checkout per CROS_RELEASE
REPO=${ROOT}/src
CROS_MANIFEST_URL=${CROS_MANIFEST_URL:-https://chromium.googlesource.com/chromiumos/manifest.git}
CROS_REPO_URL=${CROS_REPO_URL:-https://chromium.googlesource.com/external/repo.git}
OPENFYDE_MANIFEST_URL=${OPENFYDE_MANIFEST_URL:-https://github.com/openFyde/manifest.git}
ENVF="$BOARD_DIR/build.env"

log(){ printf '\n=== [%s] %s ===\n' "$BOARD_ID" "$*"; }

need_repo(){
  command -v repo >/dev/null 2>&1 && return
  [ -x "$HOME/depot_tools/repo" ] && { export PATH="$HOME/depot_tools:$PATH"; return; }
  git clone https://chromium.googlesource.com/chromium/tools/depot_tools "$HOME/depot_tools"
  export PATH="$HOME/depot_tools:$PATH"
}

cmd_sync(){
  need_repo
  mkdir -p "$REPO"; cd "$REPO"
  repo init -u "$CROS_MANIFEST_URL" --repo-url "$CROS_REPO_URL" -b "$CROS_RELEASE"
  [ -d openfyde/manifest ] || git clone "$OPENFYDE_MANIFEST_URL" openfyde/manifest -b "$OPENFYDE_MANIFEST_BRANCH"
  ln -snfr openfyde/manifest .repo/local_manifests
  repo sync -j"$(nproc)" --no-tags --optimized-fetch
}

cmd_config(){
  local ksrc="$REPO/$KSRC_REL"
  [ -d "$ksrc" ] || { echo "ERROR: kernel tree $ksrc missing - run sync first"; exit 1; }
  # 1. shared 32-bit-UEFI enabler + any board-specific config fragments
  local target="$ksrc/chromeos/config/x86_64/common.config"
  { echo "# --- iconia: shared efi-mixed ---"; cat "$HERE/config/efi-mixed.config"; } >> "$target"
  for f in "$BOARD_DIR"/config/*.config; do
    [ -e "$f" ] || continue
    { echo "# --- iconia board $BOARD_ID: $(basename "$f") ---"; cat "$f"; } >> "$target"
  done
  log "appended config fragments to $target"
  # 2. board-specific kernel patches
  for p in "$BOARD_DIR"/patches/*.patch; do
    [ -e "$p" ] || continue
    ( cd "$ksrc" && git apply --check "$p" && git apply "$p" ) && echo "applied patch $(basename "$p")"
  done
  { echo "BOARD=$OPENFYDE_BOARD"; echo "KPKG=$KPKG"; echo "KSRC=$KSRC_REL"; } > "$ENVF"
  cat "$ENVF"
  echo "Next: (cd $REPO && cros_sdk) then: setup_board --board=$OPENFYDE_BOARD"
}

cmd_build(){
  cat <<EOF

Run INSIDE the SDK chroot (cd $REPO && cros_sdk):

  setup_board --board=$OPENFYDE_BOARD
  cros_workon --board=$OPENFYDE_BOARD start $KPKG
  emerge-$OPENFYDE_BOARD $KPKG

Built kernel lands at /build/$OPENFYDE_BOARD/boot/vmlinuz (inside the chroot).
Then: scripts/build-kernel.sh --board $BOARD_ID extract
EOF
}

cmd_extract(){
  mkdir -p "$BOARD_DIR/out"
  local src="$REPO/chroot/build/$OPENFYDE_BOARD/boot/vmlinuz"
  [ -f "$src" ] || { echo "kernel not found at $src - build first"; exit 1; }
  cp -f "$src" "$BOARD_DIR/out/vmlinuz"
  local xlf; xlf=$(od -An -tu1 -j 566 -N1 "$BOARD_DIR/out/vmlinuz" | tr -d ' ')
  printf 'extracted -> boards/%s/out/vmlinuz  xloadflags.lo=0x%02x  HANDOVER32=%s\n' \
    "$BOARD_ID" "$xlf" "$([ $((xlf & 4)) -ne 0 ] && echo yes || echo NO)"
}

case "$ACTION" in
  sync) cmd_sync ;;
  config) cmd_config ;;
  build) cmd_build ;;
  extract) cmd_extract ;;
  all) cmd_sync; cmd_config; cmd_build; cmd_extract ;;
  *) echo "usage: $0 --board <id> {sync|config|build|extract|all}"; exit 2 ;;
esac
