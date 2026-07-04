#!/bin/sh
# iconia-als-brightness-install.sh — turn ON adaptive (ambient-light) brightness.
# The ALS (iio als, illuminance=lux since scale=1.0) is live and already udev-
# tagged :powerd:; powerd just never knew it existed (has_ambient_light_sensor
# was empty). We set that pref + a calibrated lux->brightness curve.
#
# Prefs live in /var/lib/power_manager (STATEFUL — persists across reboot, no
# rootfs remount needed). Revert = iconia-als-brightness-install.sh revert
#
#   ssh -i /tmp/ik root@192.168.1.31 'sh -s' < iconia-als-brightness-install.sh [revert]
set -u
DIR=/var/lib/power_manager
mkdir -p "$DIR"

# NOTE pref name is internal_backlight_als_steps (NOT ..._ambient_light_steps);
# the wrong name makes powerd silently use its built-in default curve.
STEPS_PREF="$DIR/internal_backlight_als_steps"
rm -f "$DIR/internal_backlight_ambient_light_steps"   # clean up earlier wrong name

if [ "${1:-}" = revert ]; then
    rm -f "$DIR/has_ambient_light_sensor" "$STEPS_PREF"
    echo "reverted ALS prefs (back to powerd no-ALS default 63%bat/80%ac)"
else
    echo 1 > "$DIR/has_ambient_light_sensor"
    # curve: "percent  decrease_lux  increase_lux"  (-1 = no bound; hysteresis overlaps)
    cat > "$STEPS_PREF" <<'STEPS'
15.0 -1 15
30.0 8 150
45.0 120 450
65.0 400 950
85.0 900 -1
STEPS
    echo "wrote has_ambient_light_sensor=1 + $STEPS_PREF:"
    sed 's/^/    /' "$STEPS_PREF"
fi

echo "restart powerd..."
restart powerd 2>/dev/null || { stop powerd 2>/dev/null; start powerd 2>/dev/null; } || \
    initctl restart powerd 2>/dev/null || true
sleep 2
echo "-- powerd ALS state --"
grep -iE 'ambient|light sensor|initial.*brightness|Using.*ALS' /var/log/power_manager/powerd.LATEST 2>/dev/null | tail -8
echo
echo "TEST: cover the ALS (top bezel) -> screen should dim in ~1-2s;"
echo "      shine a light on it -> it brightens. If the curve feels off, tell me"
echo "      the lux + how it looked and I'll retune the steps."
