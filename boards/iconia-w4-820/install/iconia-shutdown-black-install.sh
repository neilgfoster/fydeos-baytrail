#!/bin/sh
# iconia-shutdown-black-install.sh — install the shutdown-black Upstart job so the
# panel goes to BLACK at shutdown/reboot instead of leaving ash's white frame lit
# through power-down. See iconia-shutdown-black.conf for the rationale.
#
# Idempotent. Revert with the `revert` arg (removes the job).
# Push the .conf alongside this script, or run from the crosh host via:
#   scp both files over, then: ssh -i /tmp/ik root@IP 'sh -s' < iconia-shutdown-black-install.sh
# (the here-doc below carries the .conf inline so no separate file is needed).
set -e
JOB=/etc/init/iconia-shutdown-black.conf

echo "== remount rootfs rw =="; mount -o remount,rw /

if [ "${1:-}" = revert ]; then
    rm -f "$JOB"
    echo "removed $JOB"
else
    cat > "$JOB" <<'EOF'
# iconia-shutdown-black — kill the lingering white AFTER ash's (un-removable) shutdown
# animation. Fires on starting halt/reboot, waits for Chrome to exit, stops powerd,
# paints black via frecon, and hammers the backlight off. See the .conf in the repo
# for the full rationale (the ~1s animation flash itself is compiled into Chrome).
start on starting halt or starting reboot
task
script
  bl=/sys/class/backlight/intel_backlight
  i=0; while pgrep -x chrome >/dev/null 2>&1 && [ $i -lt 15 ]; do sleep 0.2; i=$((i+1)); done
  stop powerd 2>/dev/null || true
  frecon --clear 0x000000 --daemon --no-login --num-vts 1 2>/dev/null || true
  j=0; while [ $j -lt 8 ]; do echo 4 > "$bl/bl_power" 2>/dev/null; echo 0 > "$bl/brightness" 2>/dev/null; sleep 0.2; j=$((j+1)); done
end script
EOF
    echo "installed $JOB"
fi

sync; mount -o remount,ro / || true
echo "== job now =="; cat "$JOB" 2>/dev/null || echo "(removed)"
echo
echo "Reboot or shut down to test: screen should go BLACK (not white) during power-down."
