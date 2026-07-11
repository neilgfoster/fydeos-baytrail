#!/bin/sh
# baytrail-power-install.sh — install + load the native AXP288 power-supply drivers
# on the LIVE eMMC system over SSH. Gives ChromeOS a real charger supply (charging
# bolt) + fuel gauge, and exposes the charge-voltage knob for a longevity cap.
#
# Push these to the tablet /tmp first (from the crosh host, reading the Crostini
# fuse mount that holds ~/openfyde/axp288-stage/):
#   /tmp/extcon-core.ko.gz  /tmp/extcon-axp288.ko.gz
#   /tmp/axp288_fuel_gauge.ko.gz  /tmp/axp288_charger.ko.gz
# then:  ssh -i /tmp/ik root@192.168.1.31 'sh -s' < baytrail-power-install.sh
set -e
KVER=$(uname -r)
EXTDIR="/lib/modules/$KVER/kernel/drivers/extcon"
PWRDIR="/lib/modules/$KVER/kernel/drivers/power/supply"
ROLEDIR="/lib/modules/$KVER/kernel/drivers/usb/roles"

for f in /tmp/extcon-core.ko.gz /tmp/roles.ko.gz /tmp/extcon-axp288.ko.gz \
         /tmp/axp288_fuel_gauge.ko.gz /tmp/axp288_charger.ko.gz; do
    [ -f "$f" ] || { echo "ERROR: $f not on tablet — push it first"; exit 1; }
done

echo "== remount rootfs rw =="
mount -o remount,rw /

echo "== install modules (LoadPin needs them on the pinned rootfs) =="
mkdir -p "$EXTDIR" "$PWRDIR" "$ROLEDIR"
cp /tmp/extcon-core.ko.gz        "$EXTDIR/extcon-core.ko.gz"
cp /tmp/extcon-axp288.ko.gz      "$EXTDIR/extcon-axp288.ko.gz"
cp /tmp/roles.ko.gz              "$ROLEDIR/roles.ko.gz"
cp /tmp/axp288_fuel_gauge.ko.gz  "$PWRDIR/axp288_fuel_gauge.ko.gz"
cp /tmp/axp288_charger.ko.gz     "$PWRDIR/axp288_charger.ko.gz"
depmod "$KVER"
sync
mount -o remount,ro / || true

echo "== unload any half-bound leftovers from a previous run (ignore errors) =="
for m in axp288_charger axp288_fuel_gauge extcon_axp288; do rmmod "$m" 2>/dev/null || true; done

echo "== modprobe in dependency order (roles before extcon_axp288) =="
for m in extcon_core roles extcon_axp288 axp288_fuel_gauge axp288_charger; do
    r=$(modprobe "$m" 2>&1) || true
    echo "  modprobe $m -> ${r:-ok}"
done
sleep 2

echo "== power_supply list (want axp288_charger + axp288_fuel_gauge) =="
ls /sys/class/power_supply/

echo "== new charger supply — full attribute dump (find the cap knob) =="
for ps in /sys/class/power_supply/axp288_charger /sys/class/power_supply/axp288_fuel_gauge; do
    [ -d "$ps" ] || { echo "  ($ps not present)"; continue; }
    echo "--- ${ps##*/} ---"
    for a in "$ps"/*; do
        [ -f "$a" ] && printf '  %-28s = %s\n' "${a##*/}" "$(cat "$a" 2>/dev/null)"
    done
done

echo "== extcon cable state (VBUS detect that drives charger online) =="
for ec in /sys/class/extcon/*; do
    [ -d "$ec" ] || continue
    echo "--- ${ec##*/} ($(cat "$ec/name" 2>/dev/null)) ---"
    for s in "$ec"/cable.*/state; do
        [ -e "$s" ] && printf '  %s = %s\n' "${s%/state}" "$(cat "$s")"
    done
done

echo "== nudge powerd to re-enumerate supplies =="
restart powerd 2>/dev/null || initctl restart powerd 2>/dev/null || true
echo
echo "NEXT: plug the charger in and watch the tray — the charging bolt should appear."
echo "Paste the attribute dump back so we can set a longevity charge cap."
