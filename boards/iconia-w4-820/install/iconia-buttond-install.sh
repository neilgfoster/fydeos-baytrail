#!/bin/sh
# iconia-buttond-install.sh — install the long-press-Windows -> crosh daemon on
# the LIVE eMMC system over SSH. Run from the crosh host after pushing:
#   /tmp/iconia-buttond.gz  (static x86_64 binary, gzipped)
#   /tmp/uinput.ko.gz       (uinput module, matches deployed kernel)
#   /tmp/iconia-buttond.conf (this upstart job)
# then:  ssh -i /tmp/ik root@IP 'sh -s' < iconia-buttond-install.sh
set -e
KVER=$(uname -r)
MODDIR="/lib/modules/$KVER/kernel/drivers/input/misc"

for f in /tmp/iconia-buttond.gz /tmp/uinput.ko.gz /tmp/iconia-buttond.conf; do
    [ -f "$f" ] || { echo "ERROR: $f not on tablet — push it first"; exit 1; }
done

echo "== remount rootfs rw =="
mount -o remount,rw /

echo "== install uinput module (LoadPin needs it on the pinned rootfs) =="
mkdir -p "$MODDIR"
cp /tmp/uinput.ko.gz "$MODDIR/uinput.ko.gz"
depmod "$KVER"

echo "== install daemon binary to /usr/local/sbin (stateful, persists) =="
mkdir -p /usr/local/sbin
gunzip -c /tmp/iconia-buttond.gz > /usr/local/sbin/iconia-buttond
chmod 755 /usr/local/sbin/iconia-buttond

echo "== install upstart job =="
cp /tmp/iconia-buttond.conf /etc/init/iconia-buttond.conf

sync
mount -o remount,ro / || true

echo "== load uinput + start daemon now (no reboot) =="
modprobe uinput
initctl start iconia-buttond 2>/dev/null || start iconia-buttond 2>/dev/null || \
    { echo "(ui not up yet — will start on next 'started ui')"; }

sleep 1
echo "-- status --"
initctl status iconia-buttond 2>/dev/null || true
echo "-- daemon running? --"
pgrep -a iconia-buttond || echo "not yet running"
echo
echo "TEST: long-press the Windows button (~1s) -> a crosh tab should open."
echo "      short press still goes home."
