#!/bin/sh
# iconia-memtune-install.sh — install the memory-tuning boot job on the LIVE eMMC
# system over SSH. Push iconia-memtune.sh + .conf to /tmp first, then:
#   ssh -i /tmp/ik root@192.168.1.31 'sh -s' < iconia-memtune-install.sh
set -e
for f in /tmp/iconia-memtune.sh /tmp/iconia-memtune.conf; do
    [ -f "$f" ] || { echo "ERROR: $f not on tablet — push it first"; exit 1; }
done

echo "== remount rootfs rw =="; mount -o remount,rw /
mkdir -p /usr/local/sbin
cp /tmp/iconia-memtune.sh /usr/local/sbin/iconia-memtune
chmod 755 /usr/local/sbin/iconia-memtune
cp /tmp/iconia-memtune.conf /etc/init/iconia-memtune.conf
sync
mount -o remount,ro / || true

echo "== run now (no reboot) =="
initctl start iconia-memtune 2>/dev/null || start iconia-memtune 2>/dev/null || \
    /usr/local/sbin/iconia-memtune

echo "-- verify --"
echo "zram algo: $(cat /sys/block/zram0/comp_algorithm)"
echo "swappiness=$(cat /proc/sys/vm/swappiness) min_free_kbytes=$(cat /proc/sys/vm/min_free_kbytes) page-cluster=$(cat /proc/sys/vm/page-cluster)"
echo "DONE."
