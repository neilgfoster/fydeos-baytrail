#!/bin/sh
# baytrail-bt-probe2.sh — decide serdev-auto vs btattach-manual for the BCM2E3F BT
# on the Bay Trail HS-UART (80860F0A:00). Read-only except modprobe (harmless load).
set +e
line() { echo "===== $1 ====="; }

line "does the serdev bus exist? (CONFIG_SERIAL_DEV_BUS)"
ls -d /sys/bus/serial 2>&1
[ -d /sys/bus/serial ] && echo "SERDEV PRESENT" || echo "SERDEV ABSENT -> auto hci_bcm unavailable; use btattach"

line "kernel config for serdev / bcm hci (if config readable)"
for f in /proc/config.gz /boot/config-$(uname -r) /lib/modules/$(uname -r)/config; do
  [ -e "$f" ] && { echo "-- $f"; (zcat "$f" 2>/dev/null || cat "$f") | grep -iE 'SERIAL_DEV_BUS|HCIUART|HCIBCM|BT_HCIUART_BCM|SERIAL_8250_DW|SERIAL_8250_LPSS'; break; }
done

line "BT hci_uart / btbcm modules available to load?"
for m in hci_uart btbcm hci_bcm; do
  p=$(modprobe -n -v "$m" 2>&1)
  echo "$m: $p"
done
echo "-- try loading hci_uart + btbcm:"
modprobe hci_uart 2>&1; modprobe btbcm 2>&1
lsmod | grep -iE 'hci_uart|btbcm|bcm' || echo "(still not loaded)"

line "BCM2E3F:00 node — driver bound + properties"
D=/sys/bus/acpi/devices/BCM2E3F:00
echo "driver -> $(readlink -f $D/driver 2>/dev/null || echo NONE)"
echo "physical_node -> $(readlink -f $D/physical_node 2>/dev/null || echo NONE)"
cat $D/status 2>/dev/null
# ACPI _CRS-derived props (baud, parent uart, gpios) if exposed
for p in $D/uid $D/hid $D/path; do [ -e "$p" ] && echo "$(basename $p)=$(cat $p)"; done

line "the HS-UART parent 80860F0A:00 — driver + which ttyS"
for U in /sys/bus/acpi/devices/80860F0A:*; do
  [ -e "$U" ] || continue
  echo "-- $U  status=$(cat $U/status 2>/dev/null)"
  echo "   driver -> $(readlink -f $U/driver 2>/dev/null || echo NONE)"
  pn=$(readlink -f $U/physical_node 2>/dev/null)
  echo "   physical_node -> ${pn:-NONE}"
  [ -n "$pn" ] && find "$pn" -maxdepth 3 -name 'ttyS*' 2>/dev/null | head
done

line "map every ttyS to its device path (find the BT one)"
for t in /sys/class/tty/ttyS*; do
  dev=$(readlink -f "$t/device" 2>/dev/null)
  echo "$(basename $t) -> ${dev:-none}"
done

line "dmesg: 8250/dw/LPSS UART + serdev + BCM2E3F"
dmesg 2>&1 | grep -iE '8250|dw-apb|LPSS|80860F0A|BCM2E3F|serdev|tty.*enabled' | tail -30

echo "===== END PROBE2 ====="
