#!/bin/sh
# iconia-desktop-mode-install.sh — use the FydeOS laptop/tablet toggle (no forced mode).
#
# History of this decision:
#   session 5 : --force-tablet-mode=touch_view  (always tablet)
#   session 10: --force-tablet-mode=clamshell   (always desktop, user pref)
#   session 12: NO force flag at all.
#
# session 12 (2026-07-07): with auto-rotate now WORKING (see accel module /
# iconia-accel-rotation-install.sh), the user wants the real FydeOS laptop/tablet
# switch instead of a pinned mode — laptop mode is more productive on an external
# monitor, tablet mode auto-rotates correctly bare. FydeOS boots this convertible
# (cros_config form-factor=CHROMESLATE, is-lid-convertible=true) to LAPTOP by
# default and exposes a Laptop/Tablet toggle (Local State
# `show_switch_tablet_laptop_button`). There is NO FydeOS pref for "tablet by
# default AND keep the toggle" — forcing tablet (touch_view) makes it tablet-only
# and kills the toggle, so we leave the mode UNforced and accept laptop-default.
#
# This script therefore just REMOVES any --force-tablet-mode flag and keeps the OSK
# available. Idempotent; needs a UI restart (closes tabs).
#
#   ssh -i /tmp/ik root@192.168.1.31 'sh -s' < iconia-desktop-mode-install.sh
set -e
CONF=/etc/chrome_dev.conf

echo "== remount rootfs rw =="; mount -o remount,rw /

# Drop any pinned tablet/clamshell mode so the FydeOS toggle drives the UI.
if grep -q '^--force-tablet-mode=' "$CONF"; then
    sed -i '/^--force-tablet-mode=/d' "$CONF"
    echo "removed --force-tablet-mode (mode now via FydeOS toggle; laptop default)"
else
    echo "no --force-tablet-mode present (already toggle-driven)"
fi

# OSK must stay forced-available so a bare tablet can still type (session 5).
grep -qxF '--enable-virtual-keyboard' "$CONF" || echo '--enable-virtual-keyboard' >> "$CONF"

sync; mount -o remount,ro / || true

echo "== chrome_dev.conf (non-comment) now =="
grep -vE '^\s*#|^\s*$' "$CONF"
echo
echo "== restarting UI (this CLOSES open tabs) =="
restart ui 2>/dev/null || { stop ui 2>/dev/null; start ui 2>/dev/null; }
echo "UI restarted. Boots to laptop; use the FydeOS toggle for tablet (auto-rotates)."
