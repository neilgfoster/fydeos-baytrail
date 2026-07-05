#!/bin/sh
# iconia-bt-survey.sh — read-only Bluetooth diagnosis for the Acer Iconia W4-820.
# Goal: find why there is no hci0. Identify the BCM controller, how it's wired
# (UART/serdev vs USB), whether a driver is bound, and which .hcd firmware it wants.
# Run ON THE TABLET (root). Purely read-only; changes nothing.
set +e
line() { echo "===== $1 ====="; }

line "kernel / uname"
uname -a

line "hci devices (hciconfig / btmgmt)"
hciconfig -a 2>&1
command -v btmgmt >/dev/null 2>&1 && btmgmt info 2>&1

line "rfkill (is BT soft/hard blocked?)"
rfkill list 2>&1

line "bluetooth-related dmesg"
dmesg 2>&1 | grep -iE 'blue|hci|bcm|brcm|btbcm|serdev|uart|4343|43241|obda|rt' | tail -60

line "loaded bt modules"
lsmod 2>&1 | grep -iE 'bluetooth|btbcm|btintel|hci_uart|btusb|bcm|btrtl|serdev' || echo "(none)"

line "serial / UART devices (serdev host for onboard BT)"
ls -l /sys/bus/serial/devices/ 2>&1
ls -l /dev/ttyS* /dev/ttyUSB* 2>&1

line "ACPI devices likely to be the BT UART node (BCM2E*, OBDA, etc.)"
ls /sys/bus/acpi/devices/ 2>&1 | grep -iE 'BCM|OBDA|BSG|8087|BTH' || echo "(no obvious BT ACPI id)"
for d in /sys/bus/acpi/devices/*BCM* /sys/bus/acpi/devices/*OBDA*; do
  [ -e "$d" ] || continue
  echo "-- $d"; cat "$d/status" 2>/dev/null; cat "$d/uid" 2>/dev/null
  echo "  driver: $(readlink -f "$d/driver" 2>/dev/null || echo none)"
done

line "USB devices (rule out USB BT)"
lsusb 2>&1 | grep -iE 'blue|bcm|broadcom|0a5c' || echo "(no USB BT)"

line "BCM .hcd firmware present in /lib/firmware/brcm ?"
ls -l /lib/firmware/brcm/ 2>&1 | grep -iE '\.hcd|bcm' || echo "(no BCM .hcd firmware staged)"

line "what firmware did the kernel REQUEST (btbcm)"
dmesg 2>&1 | grep -iE 'btbcm|Patch|\.hcd|falling back|failed to' | tail -20

line "hciattach available? (manual UART attach fallback)"
command -v hciattach 2>&1 || echo "(no hciattach)"
command -v btattach 2>&1 || echo "(no btattach)"

echo "===== END SURVEY ====="
