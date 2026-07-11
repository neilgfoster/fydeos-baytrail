#!/bin/sh
# baytrail-bt-deploy.sh — install the #11 BT-enabled kernel + hci_uart module on the
# tablet over SSH. Expects /tmp/vmlinuz, /tmp/hci_uart.ko.gz, /tmp/btbcm.ko.gz
# already scp'd in. Writes new vmlinuz to eMMC ESP, drops the modules into the tree,
# runs depmod, leaves rootfs ro. Reboot afterward to pick up serdev+DW-UART+hci_uart.
set -e
KV=6.6.76-gabcfb16364e1
CON=/dev/tty1
say() { echo "ICONIA-BT: $*"; echo "ICONIA-BT: $*" > "$CON" 2>/dev/null || true; }

[ -f /tmp/vmlinuz ] || { say "FATAL: /tmp/vmlinuz missing (scp it first)"; exit 1; }
[ -f /tmp/hci_uart.ko.gz ] || { say "FATAL: /tmp/hci_uart.ko.gz missing"; exit 1; }

XLF=$(od -An -tx1 -j566 -N2 /tmp/vmlinuz | tr -s ' ')
say "staged vmlinuz xloadflags=[$XLF] (want '3f 00')"

# --- 1. new vmlinuz -> eMMC ESP /syslinux/vmlinuz.A ---
ESP="$(rootdev -s -d)p12"
M=/mnt/baytrail-eesp; mkdir -p "$M"
mount "$ESP" "$M" 2>/dev/null || { say "FATAL: cannot mount eMMC ESP $ESP"; exit 1; }
cp -f "$M/syslinux/vmlinuz.A" "$M/syslinux/vmlinuz.A.bak-bt" 2>/dev/null || true
cp -f /tmp/vmlinuz "$M/syslinux/vmlinuz.A"
sync
say "vmlinuz.A updated (backup: vmlinuz.A.bak-bt); new xlf=$(od -An -tx1 -j566 -N2 "$M/syslinux/vmlinuz.A" | tr -s ' ')"
umount "$M"

# --- 2. modules -> rootfs tree + depmod ---
mount -o remount,rw / 2>/dev/null || { say "FATAL: cannot remount rw"; exit 1; }
BT=/lib/modules/$KV/kernel/drivers/bluetooth
mkdir -p "$BT"
cp -f /tmp/hci_uart.ko.gz "$BT/hci_uart.ko.gz"
cp -f /tmp/btbcm.ko.gz    "$BT/btbcm.ko.gz"
say "modules placed: $(ls -1 $BT/hci_uart.ko.gz $BT/btbcm.ko.gz 2>&1)"
depmod "$KV"
HITS=$(grep -c 'hci_uart' /lib/modules/$KV/modules.dep 2>/dev/null)
say "post-depmod modules.dep hci_uart entries=$HITS (should be >0)"
sync
mount -o remount,ro / 2>/dev/null || true

say "=== DONE. Reboot the tablet, then check for hci0. ==="
