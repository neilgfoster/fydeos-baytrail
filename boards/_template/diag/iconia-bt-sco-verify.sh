#!/bin/sh
# iconia-bt-sco-verify.sh — after a reboot with the SCO-transport hci_uart module,
# confirm the routing took and that an HFP SCO link now produces a capture stream.
# Runs ON THE TABLET.
say() { echo "ICONIA-SCO-VERIFY: $*"; }

say "1) kernel applied the routing at bring-up? (expect the iconia dev_info line)"
dmesg | grep -i 'iconia: forcing SCO routing' || say "  NOT FOUND — module didn't load or HID mismatch"

say "2) hci0 state (Floss should own it):"
hciconfig hci0 2>/dev/null | grep -E 'BD Address|UP|RUNNING' || say "  hci0 not up"

say "3) any SCO connection / codec activity in dmesg since boot:"
dmesg | grep -iE 'sco|esco|voice|air.?coding' | tail -8 || say "  (none yet — connect a headset + start a call first)"

say ""
say "=== NOW pair/connect a HFP headset, join any call (Meet/record), then re-run"
say "    steps 4-5 below to check for a live capture stream. ==="

say "4) CRAS input nodes (look for the BT headset as an INPUT):"
which cras_test_client >/dev/null 2>&1 && cras_test_client --dump_server_info 2>/dev/null \
  | sed -n '/Input Devices/,/Attached clients/p' || say "  cras_test_client unavailable"

say "5) capture 3s from default input; non-zero size + non-silent = SCO mic works:"
OUT=/tmp/sco_cap.raw
if which cras_test_client >/dev/null 2>&1; then
  cras_test_client --capture_file "$OUT" --duration 3 --num_channels 1 --rate 16000 2>/dev/null
  sz=$(wc -c < "$OUT" 2>/dev/null || echo 0)
  say "  captured $sz bytes -> $OUT (0 = still no SCO stream; ~96000 = 3s@16k mono)"
fi
