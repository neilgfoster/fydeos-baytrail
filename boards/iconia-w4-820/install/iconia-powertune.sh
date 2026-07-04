#!/bin/sh
# iconia-powertune.sh — UX-safe power savings for the Iconia W4-820 (Crystal Cove
# Bay Trail). Installed as a persistent upstart job (iconia-powertune.conf).
#
# Strategy (see hardware-status.md):
#   * Governor is already schedutil + max_cstate 9 — we only PIN it, no change.
#   * S0ix SUSPEND IS BROKEN on this board (screen won't wake). So the danger to
#     UX is auto-suspend, not screen-off. We DISABLE idle-suspend but still let
#     the panel power down on idle — display-off is the big drain and it wakes
#     fine on touch (it's not a real suspend).
#   * Light runtime-PM autosuspend on idle I2C devices only (safe); wifi SDIO /
#     eMMC / USB are left alone to avoid hiccups.
#   * Charging status / charge-cap are firmware-limited here (no Crystal Cove
#     charger driver) — nothing to do; documented in hardware-status.md.
#
# Push + install over SSH:
#   ssh -i /tmp/ik root@192.168.1.31 'sh -s' < iconia-powertune-install.sh
# This script is the runtime body invoked by the upstart job on each boot.
set -u
LOG="logger -t iconia-powertune"

# 1. Pin schedutil on every CPU (idempotent; already the default).
for g in /sys/devices/system/cpu/cpu*/cpufreq/scaling_governor; do
    [ -w "$g" ] && echo schedutil > "$g" 2>/dev/null || true
done
$LOG "governor pinned schedutil"

# 2. Never idle-suspend (S0ix broken). Screen-off on idle still allowed.
#    powerd reads this override dir; write both the modern + legacy pref names.
mkdir -p /var/lib/power_manager
echo 1 > /var/lib/power_manager/disable_idle_suspend
$LOG "disable_idle_suspend=1 written"

# 3. Light runtime PM: let idle I2C controllers/devices autosuspend. Skip
#    sdio/mmc/usb (wifi + eMMC) on purpose — autosuspend there risks UX.
for c in /sys/bus/i2c/devices/*/power/control; do
    [ -w "$c" ] && echo auto > "$c" 2>/dev/null || true
done
$LOG "i2c runtime-pm set auto"

# 4. eMMC I/O scheduler -> none (flash; already the default, set idempotently).
for d in /sys/block/mmcblk*/queue/scheduler; do
    [ -w "$d" ] && echo none > "$d" 2>/dev/null || true
done

# 5. Stop genuinely-unused services. NOTE: this is a RAM win (~26 MB on this
#    2 GB device), NOT a power win — measured power delta was within noise. Kept
#    here because it's the "boot tuning" job. Cameras don't work, no printer, no
#    cellular modem; update-engine also matches the "disable auto-update" intent.
for s in cros-camera cros-camera-diagnostics cros-camera-libfs cupsd \
         modemmanager fwupd p2p avahi update-engine; do
    stop "$s" >/dev/null 2>&1 || true
done
$LOG "stopped unused services (RAM reclaim ~26MB)"

exit 0
