#!/usr/bin/env bash
# build-kernel.sh - build an openFyde kernel with CONFIG_EFI_MIXED (32-bit EFI
# handover) so it boots on 32-bit UEFI firmware (Acer Iconia W4-820 / Bay Trail).
#
# Run in a beefy x86_64 Linux environment (a FydeOS Crostini container works:
# needs ~120 GB free disk + 16 GB RAM + several hours for the first sync/build).
#
# STATUS: WORK IN PROGRESS. The openFyde board name, kernel package name and
# kernel config path are discovered from the synced tree (see the DISCOVER
# section). Values get pinned into build.env on first run; review before trusting.
#
# Usage:
#   scripts/build-kernel.sh sync      # repo init + sync openFyde (slow, one-time)
#   scripts/build-kernel.sh config    # discover board/kernel + apply efi-mixed.config
#   scripts/build-kernel.sh build     # emerge just the kernel
#   scripts/build-kernel.sh extract   # copy the resulting vmlinuz to ./out/
#   scripts/build-kernel.sh all       # sync -> config -> build -> extract
set -euo pipefail

ROOT=${OPENFYDE_ROOT:-$HOME/openfyde}
REPO=${ROOT}/src
# openFyde layers on top of the UPSTREAM ChromiumOS manifest via local_manifests
# (per openFyde/getting-started). Base = the ChromiumOS release; openFyde overrides.
CROS_MANIFEST_URL=${CROS_MANIFEST_URL:-https://chromium.googlesource.com/chromiumos/manifest.git}
CROS_REPO_URL=${CROS_REPO_URL:-https://chromium.googlesource.com/external/repo.git}
CROS_RELEASE=${CROS_RELEASE:-release-R138-16295.B}   # matches USB kernel 6.6 (Dec 2025)
OPENFYDE_MANIFEST_URL=${OPENFYDE_MANIFEST_URL:-https://github.com/openFyde/manifest.git}
MANIFEST_BRANCH=${MANIFEST_BRANCH:-r138-dev}
BOARD=${BOARD:-amd64-openfyde_slim}            # matches USB board "amd64-fydeos_slim"
HERE=$(cd "$(dirname "$0")/.." && pwd)
FRAG=${HERE}/config/efi-mixed.config
ENVF=${HERE}/build.env

log(){ printf '\n=== %s ===\n' "$*"; }

need_depot_tools(){
  if ! command -v repo >/dev/null 2>&1; then
    log "installing depot_tools"
    git clone https://chromium.googlesource.com/chromium/tools/depot_tools "$HOME/depot_tools"
    export PATH="$HOME/depot_tools:$PATH"
    echo 'NOTE: add $HOME/depot_tools to PATH permanently'
  fi
}

cmd_sync(){
  need_depot_tools
  mkdir -p "$REPO"; cd "$REPO"
  # 1. base = upstream ChromiumOS release
  repo init -u "$CROS_MANIFEST_URL" --repo-url "$CROS_REPO_URL" -b "$CROS_RELEASE"
  # 2. overlay the openFyde manifest via local_manifests
  if [ ! -d openfyde/manifest ]; then
    git clone "$OPENFYDE_MANIFEST_URL" openfyde/manifest -b "$MANIFEST_BRANCH"
  fi
  ln -snfr openfyde/manifest .repo/local_manifests
  # 3. sync (long; resumable)
  repo sync -j"$(nproc)"
}

# DISCOVER: find the actual board, kernel package and config dir in the synced tree.
cmd_config(){
  cd "$REPO"
  log "discovering kernel package + config path"
  # ChromiumOS kernel ebuilds live under src/third_party/chromiumos-overlay/sys-kernel/
  KPKG=${KPKG_OVERRIDE:-chromeos-kernel-6_6}   # USB ships 6.6; confirm the ebuild exists
  # kernel config fragments live under the kernel source tree chromeos/config/
  KSRC=src/third_party/kernel/v6.6
  {
    echo "BOARD=$BOARD"
    echo "KPKG=${KPKG:-UNKNOWN-set-manually}"
    echo "KSRC=${KSRC:-UNKNOWN-set-manually}"
  } > "$ENVF"
  cat "$ENVF"

  if [ -n "${KSRC:-}" ] && [ -d "$REPO/$KSRC/chromeos/config" ]; then
    # append our fragment to the x86_64 config so it is merged at build time
    TARGET="$REPO/$KSRC/chromeos/config/x86_64/common.config"
    log "appending efi-mixed.config to $TARGET"
    { echo "# --- iconia: 32-bit EFI handover ---"; cat "$FRAG"; } >> "$TARGET"
  else
    echo "WARNING: kernel config dir not found; add these by hand to the x86_64 config:"; cat "$FRAG"
  fi
  echo "Enter the SDK with: (cd $REPO && cros_sdk) then run: setup_board --board=$BOARD"
}

cmd_build(){
  # shellcheck disable=SC1090
  source "$ENVF"
  cat <<EOF
Run these INSIDE the SDK chroot (cros_sdk from $REPO):

  setup_board --board=$BOARD
  cros_workon --board=$BOARD start ${KPKG:-chromeos-kernel-...}
  emerge-$BOARD ${KPKG:-chromeos-kernel-...}

The built kernel image lands under /build/$BOARD/boot/ (vmlinuz).
EOF
}

cmd_extract(){
  # shellcheck disable=SC1090
  source "$ENVF"
  mkdir -p "$HERE/out"
  SRC="$REPO/chroot/build/$BOARD/boot/vmlinuz"
  if [ -f "$SRC" ]; then
    cp -f "$SRC" "$HERE/out/vmlinuz"
    XLF=$(od -An -tu1 -j 566 -N1 "$HERE/out/vmlinuz" | tr -d ' ')
    printf 'extracted -> out/vmlinuz  xloadflags.lo=0x%02x  HANDOVER32=%s\n' \
      "$XLF" "$([ $((XLF & 4)) -ne 0 ] && echo yes || echo NO)"
  else
    echo "kernel not found at $SRC - build first, or set path manually"; exit 1
  fi
}

case "${1:-all}" in
  sync) cmd_sync ;;
  config) cmd_config ;;
  build) cmd_build ;;
  extract) cmd_extract ;;
  all) cmd_sync; cmd_config; cmd_build; cmd_extract ;;
  *) echo "usage: $0 {sync|config|build|extract|all}"; exit 2 ;;
esac
