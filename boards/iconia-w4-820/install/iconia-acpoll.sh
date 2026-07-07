#!/bin/sh
# iconia-acpoll.sh — periodic power_supply refresh poke for the Iconia W4-820.
#
# WHY: AC/battery is a ULPMC-style EC on the fragile Bay Trail i2c-0 bus, behind a
# level-triggered ACPI GPIO event (\_SB.GPO2 pin 18 = INT33FC:02@18). That event
# STORMED (~50 IRQ/s) because its I2C interrupt-clear read kept timing out on the
# wedged bus — draining power (blocked C7S) and starving the bus so AC/battery
# froze at their boot values. We mute the event via kernel cmdline
#   gpiolib_acpi.ignore_interrupt=INT33FC:02@18
# (see the iconia-ac-gpe-storm note). That kills the storm, but also removes the
# ONLY power_supply push-notify path — so powerd/UI otherwise update only on their
# slow, erratic internal poll (user saw the tray icon lag / stick).
#
# This job restores a reliable cadence: emit a udev 'change' on the power_supply
# nodes every few seconds so powerd re-reads and repaints the tray promptly.
# Cost is trivial — one EC read every few seconds; the storm was ~250x this rate.
set -u
INTERVAL="${1:-5}"
logger -t iconia-acpoll "starting power_supply UI poke every ${INTERVAL}s"
while true; do
    udevadm trigger --action=change --subsystem-match=power_supply 2>/dev/null
    sleep "$INTERVAL"
done
