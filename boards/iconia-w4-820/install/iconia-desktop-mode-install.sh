#!/bin/sh
# iconia-desktop-mode-install.sh — force ChromeOS into permanent clamshell/desktop UI.
#
# User preference: the Iconia should ALWAYS present the desktop (clamshell) UX —
# windowed apps, no forced tablet shell — even when used bare as a tablet. This
# replaces the earlier `--force-tablet-mode=touch_view` (always-tablet) with
# `--force-tablet-mode=clamshell` (always-desktop). The OSK still works because it
# is forced available via `--enable-virtual-keyboard` (set in session 5), so you can
# still type on the touchscreen with no physical keyboard attached.
#
# Idempotent; needs a UI restart (closes tabs). Revert with the `revert` arg
# (restores touch_view).
#
#   ssh -i /tmp/ik root@192.168.1.31 'sh -s' < iconia-desktop-mode-install.sh [revert]
set -e
CONF=/etc/chrome_dev.conf

echo "== remount rootfs rw =="; mount -o remount,rw /

if [ "${1:-}" = revert ]; then
    if grep -q '^--force-tablet-mode=' "$CONF"; then
        sed -i 's/^--force-tablet-mode=.*/--force-tablet-mode=touch_view/' "$CONF"
    else
        echo '--force-tablet-mode=touch_view' >> "$CONF"
    fi
    echo "reverted to tablet mode (touch_view)"
else
    if grep -q '^--force-tablet-mode=' "$CONF"; then
        sed -i 's/^--force-tablet-mode=.*/--force-tablet-mode=clamshell/' "$CONF"
    else
        echo '--force-tablet-mode=clamshell' >> "$CONF"
    fi
    echo "set permanent desktop/clamshell mode (clamshell)"
fi

# Belt-and-suspenders: OSK must stay forced-available so a bare tablet can still type.
grep -qxF '--enable-virtual-keyboard' "$CONF" || echo '--enable-virtual-keyboard' >> "$CONF"

sync; mount -o remount,ro / || true

echo "== chrome_dev.conf (non-comment) now =="
grep -vE '^\s*#|^\s*$' "$CONF"
echo
echo "== restarting UI (this CLOSES open tabs) =="
restart ui 2>/dev/null || { stop ui 2>/dev/null; start ui 2>/dev/null; }
echo "UI restarted. Log back in — UI should now be desktop/clamshell in every orientation."
