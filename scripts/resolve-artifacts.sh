#!/bin/bash
# resolve-artifacts.sh — the cache-lookup step of the prepare-USB flow.
#
#   scripts/resolve-artifacts.sh --board <id> [--download]
#
# Computes the build tag from the kernel version + a fingerprint of the config
# fragments/patches/sources, then checks whether that build already exists as a
# GitHub Release:
#   * CACHE HIT  -> (with --download) pulls the bundle into .artifact-cache/<tag>/
#                   and verifies sha256s against the release's bundle.sha256.
#   * CACHE MISS -> prints the exact build+publish commands to run.
#
# Exit: 0 = cache hit (ready to inject), 10 = cache miss (build needed), 1 = error.
# Requires: gh (authed), sha256sum. See docs/artifact-cache.md.
set -euo pipefail

BOARD=""; DOWNLOAD=0
while [ $# -gt 0 ]; do
  case "$1" in
    --board) BOARD="$2"; shift 2 ;;
    --download) DOWNLOAD=1; shift ;;
    *) echo "unknown arg: $1" >&2; exit 1 ;;
  esac
done
[ -n "$BOARD" ] || { echo "usage: $0 --board <id> [--download]" >&2; exit 1; }

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
BDIR="$ROOT/boards/$BOARD"
MANIFEST="$BDIR/artifacts.manifest"
[ -f "$MANIFEST" ] || { echo "no manifest: $MANIFEST" >&2; exit 1; }
# shellcheck disable=SC1090
. "$BDIR/board.env"; . "$MANIFEST"

# --- optional: check the detected stock kernel against the match rule ---
PROFILE="$BDIR/usb-profile.env"
if [ -f "$PROFILE" ]; then
  KVER_A="$(sed -n 's/^KVER_A="\?\([^"]*\)"\?/\1/p' "$PROFILE")"
  # shellcheck disable=SC2254
  case "$KVER_A" in
    $MATCH_STOCK_KERNEL) : ;;
    "") echo "note: no KVER_A in usb-profile.env (run inspect-usb.sh first)" >&2 ;;
    *) echo "WARNING: detected stock kernel '$KVER_A' does not match" \
            "MATCH_STOCK_KERNEL='$MATCH_STOCK_KERNEL' — this build may not fit." >&2 ;;
  esac
fi

# --- fingerprint the build inputs -> deterministic tag ---
fp_files() {
  for pat in $FINGERPRINT_INPUTS; do
    for f in $ROOT/$pat; do [ -f "$f" ] && echo "$f"; done
  done | sort -u
}
FP="$(fp_files | xargs cat | sha256sum | cut -c1-12)"
TAG="${BUILD_TAG_BASE}-${FP}"
echo "board            : $BOARD ($DEVICE_NAME)"
echo "kernel UTS       : $BUILD_KERNEL_UTS"
echo "config fingerprint: $FP"
echo "build tag        : $TAG"

# --- cache lookup ---
if ! gh release view "$TAG" >/dev/null 2>&1; then
  echo
  echo "== CACHE MISS =="
  echo "No release '$TAG'. Build then publish:"
  echo "  scripts/build-kernel-standalone.sh --board $BOARD    # produces vmlinuz + modules"
  echo "  gcc -O2 -static -o $BDIR/install/iconia-buttond $BDIR/install/iconia-buttond.c"
  echo "  scripts/publish-artifacts.sh --board $BOARD          # creates release '$TAG'"
  exit 10
fi

echo
echo "== CACHE HIT: release '$TAG' exists =="
if [ "$DOWNLOAD" -eq 0 ]; then
  echo "(re-run with --download to fetch + verify the bundle)"
  exit 0
fi

DEST="$ROOT/.artifact-cache/$TAG"
mkdir -p "$DEST"
echo "downloading bundle -> $DEST"
gh release download "$TAG" --dir "$DEST" --clobber
if [ -f "$DEST/bundle.sha256" ]; then
  echo "verifying sha256s..."
  ( cd "$DEST" && sha256sum -c bundle.sha256 )
  echo "OK — bundle verified. Inject with scripts/inject-kernel.sh --board $BOARD --from $DEST"
else
  echo "WARNING: no bundle.sha256 in release — cannot verify integrity." >&2
fi
