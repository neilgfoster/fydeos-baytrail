#!/bin/sh
# baytrail-bt-sco-deploy.sh — install the SCO-transport-routing hci_uart module on the
# tablet. Runs ON THE TABLET; expects /tmp/hci_uart.ko.gz already scp'd in (the #11
# kernel with the bt-sco-transport-routing.patch, vermagic 6.6.76-gabcfb16364e1).
#
# The BCM4324B3 defaults SCO to its PCM pins (not wired to the RT5640 here), so HFP
# mic never reaches CRAS. This module forces SCO routing to the HCI transport during
# bcm_setup(), which re-runs on every hci0 open — so it survives Floss's HCI_Reset.
#
# We just drop the module into the tree + depmod, then reboot: on cold bring-up
# bcm_setup() applies the routing before Floss ever opens hci0. Clean and reliable
# (rmmod-while-Floss-holds-hci0 is fragile; a reboot is deterministic).
set -e
say() { echo "ICONIA-SCO-DEPLOY: $*"; }

[ -f /tmp/hci_uart.ko.gz ] || { say "FATAL: /tmp/hci_uart.ko.gz missing (scp it first)"; exit 1; }

KREL="$(uname -r)"                       # 6.6.76-gabcfb16364e1
DEST="/lib/modules/$KREL/kernel/drivers/bluetooth/hci_uart.ko.gz"
say "target kernel: $KREL"
[ -f "$DEST" ] || { say "FATAL: $DEST not present — wrong kernel deployed?"; exit 1; }

say "verifying staged module vermagic matches running kernel ..."
STAGED="$(zcat /tmp/hci_uart.ko.gz | grep -a -m1 -o 'vermagic=[^ ]*' | sed 's/vermagic=//')"
say "  staged vermagic: $STAGED"
[ "$STAGED" = "$KREL" ] || { say "FATAL: vermagic mismatch ($STAGED != $KREL) — rebuild"; exit 1; }

say "remounting / rw and installing module ..."
mount -o remount,rw /
cp "$DEST" "${DEST}.bak.$(date +%s)"     # keep a rollback copy
cp /tmp/hci_uart.ko.gz "$DEST"
depmod -a "$KREL"                         # stale modules.dep blocks autoload
sync
mount -o remount,ro / 2>/dev/null || true

say "module installed + depmod done. Rebooting so bcm_setup applies SCO routing"
say "at hci0 bring-up (before Floss). After reboot, run: baytrail-bt-sco-verify.sh"
sync
reboot
