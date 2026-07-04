#!/bin/sh
# iconia-chrome-memtune-install.sh — append low-RAM Chrome flags to chrome_dev.conf
# (2 GB device). Moderate profile: keeps site isolation. Needs a UI restart (closes
# tabs). Idempotent; revert with the `revert` arg.
#
#   ssh -i /tmp/ik root@192.168.1.31 'sh -s' < iconia-chrome-memtune-install.sh [revert]
set -e
CONF=/etc/chrome_dev.conf
FLAGS="--enable-low-end-device-mode --renderer-process-limit=8"

echo "== remount rootfs rw =="; mount -o remount,rw /

if [ "${1:-}" = revert ]; then
    sed -i '/^--enable-low-end-device-mode$/d;/^--renderer-process-limit=8$/d' "$CONF"
    echo "reverted low-RAM chrome flags"
else
    for f in $FLAGS; do
        grep -qxF "$f" "$CONF" || echo "$f" >> "$CONF"
    done
    echo "added: $FLAGS"
fi
sync; mount -o remount,ro / || true

echo "== chrome_dev.conf (non-comment) now =="
grep -vE '^\s*#|^\s*$' "$CONF"
echo
echo "== restarting UI (this CLOSES open tabs) =="
restart ui 2>/dev/null || { stop ui 2>/dev/null; start ui 2>/dev/null; }
echo "UI restarted. Log back in, reopen your usual tabs, then run the verify command."
