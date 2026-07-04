#!/bin/bash
# publish-artifacts.sh — the cache-fill step: bundle this board's build outputs
# into a GitHub Release keyed by the same fingerprint tag resolve-artifacts.sh
# computes, so a future run gets a cache hit.
#
#   scripts/publish-artifacts.sh --board <id> [--notes "..."]
#
# Gathers BUNDLE_ASSETS from the manifest, writes bundle.sha256, and creates (or
# updates) the release. Requires: gh (authed), sha256sum. See docs/artifact-cache.md.
set -euo pipefail

BOARD=""; NOTES=""
while [ $# -gt 0 ]; do
  case "$1" in
    --board) BOARD="$2"; shift 2 ;;
    --notes) NOTES="$2"; shift 2 ;;
    *) echo "unknown arg: $1" >&2; exit 1 ;;
  esac
done
[ -n "$BOARD" ] || { echo "usage: $0 --board <id> [--notes ...]" >&2; exit 1; }

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
BDIR="$ROOT/boards/$BOARD"
MANIFEST="$BDIR/artifacts.manifest"
[ -f "$MANIFEST" ] || { echo "no manifest: $MANIFEST" >&2; exit 1; }
# shellcheck disable=SC1090
. "$BDIR/board.env"; . "$MANIFEST"

# Recompute the tag exactly as resolve-artifacts.sh does (keep in sync).
fp_files() {
  for pat in $FINGERPRINT_INPUTS; do
    for f in $ROOT/$pat; do [ -f "$f" ] && echo "$f"; done
  done | sort -u
}
FP="$(fp_files | xargs cat | sha256sum | cut -c1-12)"
TAG="${BUILD_TAG_BASE}-${FP}"

STAGE="$ROOT/.artifact-cache/_publish-$TAG"
rm -rf "$STAGE"; mkdir -p "$STAGE"

echo "staging bundle assets for tag $TAG"
# BUNDLE_ASSETS: 'NAME  LOCAL_PATH' per line
echo "$BUNDLE_ASSETS" | while read -r name path; do
  [ -n "${name:-}" ] || continue
  src="$(eval echo "$path")"   # expand ~ and globs
  if [ ! -f "$src" ]; then
    echo "ERROR: bundle member '$name' not found at '$src' — build first." >&2
    exit 1
  fi
  cp "$src" "$STAGE/$name"
  echo "  + $name  <-  $src"
done

( cd "$STAGE" && sha256sum ./* > bundle.sha256 )
echo "bundle.sha256:"; sed 's/^/  /' "$STAGE/bundle.sha256"

[ -n "$NOTES" ] || NOTES="Build for $DEVICE_NAME — kernel $BUILD_KERNEL_UTS, config fingerprint $FP."
if gh release view "$TAG" >/dev/null 2>&1; then
  echo "release $TAG exists — uploading/clobbering assets"
  gh release upload "$TAG" "$STAGE"/* --clobber
else
  echo "creating release $TAG"
  gh release create "$TAG" "$STAGE"/* --title "$BOARD $BUILD_KERNEL_UTS ($FP)" --notes "$NOTES"
fi
echo "done. resolve-artifacts.sh --board $BOARD will now get a CACHE HIT."
