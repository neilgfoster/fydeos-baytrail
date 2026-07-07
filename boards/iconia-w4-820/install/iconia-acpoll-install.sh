#!/bin/sh
# iconia-acpoll-install.sh — install the power_supply UI-poke boot job on the LIVE
# eMMC system over SSH. Push iconia-acpoll.sh + .conf to /tmp first, then:
#   ssh -i /tmp/ik root@192.168.1.31 'sh -s' < iconia-acpoll-install.sh
set -e
for f in /tmp/iconia-acpoll.sh /tmp/iconia-acpoll.conf; do
    [ -f "$f" ] || { echo "ERROR: $f not on tablet — push it first"; exit 1; }
done

echo "== remount rootfs rw =="; mount -o remount,rw /
mkdir -p /usr/local/sbin
cp /tmp/iconia-acpoll.sh /usr/local/sbin/iconia-acpoll
chmod 755 /usr/local/sbin/iconia-acpoll
cp /tmp/iconia-acpoll.conf /etc/init/iconia-acpoll.conf
sync
mount -o remount,ro / || true

echo "== (re)start job now (no reboot) =="
initctl restart iconia-acpoll 2>/dev/null || initctl start iconia-acpoll 2>/dev/null || \
    start iconia-acpoll 2>/dev/null || true

sleep 2
echo "-- verify --"
initctl status iconia-acpoll 2>/dev/null || status iconia-acpoll 2>/dev/null || true
pgrep -af iconia-acpoll || echo "(poke process not found!)"
echo "DONE. Plug/unplug and watch the tray — should track within ~5s now."
