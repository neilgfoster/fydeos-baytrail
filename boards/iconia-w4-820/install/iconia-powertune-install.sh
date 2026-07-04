#!/bin/sh
# iconia-powertune-install.sh — install the UX-safe power-tuning job on the LIVE
# eMMC system over SSH. Pushes nothing else; it embeds the runtime script inline
# from the repo copy, so just:
#   ssh -i /tmp/ik root@192.168.1.31 'sh -s' < iconia-powertune-install.sh
# with iconia-powertune.sh + .conf already staged at /tmp (or edit paths below).
set -e
for f in /tmp/iconia-powertune.sh /tmp/iconia-powertune.conf; do
    [ -f "$f" ] || { echo "ERROR: $f not on tablet — push it first"; exit 1; }
done

echo "== remount rootfs rw =="
mount -o remount,rw /

echo "== install runtime script + upstart job =="
mkdir -p /usr/local/sbin
cp /tmp/iconia-powertune.sh /usr/local/sbin/iconia-powertune
chmod 755 /usr/local/sbin/iconia-powertune
cp /tmp/iconia-powertune.conf /etc/init/iconia-powertune.conf
sync
mount -o remount,ro / || true

echo "== run it now (no reboot) =="
initctl start iconia-powertune 2>/dev/null || start iconia-powertune 2>/dev/null || \
    /usr/local/sbin/iconia-powertune

echo "-- verify --"
echo "governor:        $(cat /sys/devices/system/cpu/cpu0/cpufreq/scaling_governor)"
echo "disable_idle_suspend: $(cat /var/lib/power_manager/disable_idle_suspend 2>/dev/null)"
echo "restart powerd to pick up disable_idle_suspend..."
restart powerd 2>/dev/null || initctl restart powerd 2>/dev/null || true
echo "DONE. Re-run iconia-power-measure.sh (unplugged) to compare drain."
