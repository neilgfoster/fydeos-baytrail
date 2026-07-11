#!/bin/sh
# baytrail-bt-sco-hci.sh — experiment: route BCM4324B3 SCO audio over the HCI/UART
# transport instead of the chip's PCM pins, so HFP mic/voice actually reaches CRAS.
# Broadcom vendor cmd Write_SCO_PCM_Int_Param (OGF 0x3f, OCF 0x1c):
#   byte0 sco_routing: 0=PCM 1=Transport(HCI) 2=Codec 3=I2S
#   byte1 pcm_rate, byte2 frame_type, byte3 sync_mode, byte4 clock_mode
# We set routing=1 (transport). Reversible: rerun with ROUTE=00 to restore PCM.
# Floss (btmanagerd) owns hci0 exclusively, so we stop it, poke the chip with BlueZ,
# then restart Floss. Whether routing survives Floss's HCI_Reset is what we're testing.
set +e
ROUTE="${1:-01}"   # 01=transport(HCI), 00=PCM(default)
say() { echo "ICONIA-SCO: $*"; }

say "stopping Floss (btmanagerd) to free hci0 ..."
stop btmanagerd 2>&1 || initctl stop btmanagerd 2>&1
sleep 1

say "bringing hci0 up via BlueZ tools ..."
hciconfig hci0 up 2>&1
hciconfig hci0 2>&1 | grep -E 'BD Address|UP|DOWN'

say "current supported-commands (does controller take vendor cmds?) ..."
hciconfig hci0 commands 2>/dev/null | grep -i 'Octet 0' | head -1

say ">>> sending Write_SCO_PCM_Int_Param routing=0x$ROUTE ..."
hcitool -i hci0 cmd 0x3f 0x1c "0x$ROUTE" 0x00 0x00 0x00 0x00 2>&1

say ">>> setting transparent voice setting (mSBC/CVSD over HCI) ..."
# 0x0060 = transparent air-coding (needed for SCO-over-HCI/mSBC); 0x0000 = CVSD
hciconfig hci0 voice 0x0060 2>&1
hciconfig hci0 voice 2>&1

say "restarting Floss (btmanagerd) ..."
start btmanagerd 2>&1 || initctl start btmanagerd 2>&1
sleep 2
say "btmanagerd: $(status btmanagerd 2>&1)"

say "dmesg tail:"
dmesg | grep -iE 'sco|hci0|bcm|Unknown HCI command' | tail -8
say "=== DONE. Re-select the buds mic in the UI, then retest capture. ==="
