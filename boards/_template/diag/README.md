# Diagnostic toolkit (Bay Trail) — shared prior-art

These are the **one-off diagnostic, survey and probe scripts** built while bringing
up the Acer Iconia W4-820. They are **not** part of any delivery build — they
inspect hardware, dump state, and A/B-test fixes. They live here (not in a board
dir) because the *next* Bay Trail tablet will need the same categories of probe.

They keep their `iconia-` names as honest prior-art. For a new board, copy the
relevant one into `boards/<board>/` and adapt the device paths (i2c bus numbers,
PMIC ACPI IDs, block devices all differ per unit).

## By category

| Category | Scripts | What they check |
|----------|---------|-----------------|
| **General HW sweep** | `iconia-hw-diag.sh` | one-shot dmesg / lspci / driver-bind survey |
| **Audio** | `iconia-audio-diag.sh` | `/proc/asound/cards`, SST-vs-SOF, firmware `-2` errors, UCM |
| **Backlight** | `iconia-backlight-diag.sh` | `/sys/class/backlight`, PMIC PWM cell binding |
| **WiFi** | `iconia-wifi-diag.sh`, `iconia-wifi99-diag.sh` | brcmfmac autoload, modules.dep, firmware/NVRAM presence |
| **Bluetooth** | `iconia-bt-survey.sh`, `iconia-bt-probe2.sh`, `iconia-bt-deploy.sh`, `iconia-bt-sco-*.sh`, `iconia-btnmon.c` | serdev/UART bind, hci0, SCO routing, HCI monitor |
| **Sensors / accel** | `iconia-sensor-diag.sh`, `iconia-sensor-boot.sh`, `iconia-sensor-load.sh`, `iconia-emmc-sensor-check.sh`, `iconia-emmc-armsensor.sh` | IIO devices, sensor-hub i2c, accel module load |
| **Power / battery** | `iconia-power-diag.sh`, `iconia-power-measure.sh`, `iconia-power-install.sh`, `iconia-pwr-rapl.sh`, `iconia-pwr-sample.sh`, `iconia-pwr-survey.sh`, `iconia-batlog.sh` | RAPL draw, PMIC identity, AXP288-vs-Crystal-Cove (dead end), battery gauge |
| **Memory** | `iconia-mem-survey.sh` | zram, swappiness, avail MB, Chrome proc count |
| **ESP / boot** | `iconia-esp-diag.sh`, `iconia-esp99-diag.sh` | ESP fill, kernel copy integrity, grub.cfg prefix |
| **eMMC / install debug** | `iconia-emmc-debug.sh`, `iconia-emmc-getlog.sh`, `iconia-emmc-armaudio.sh` | pull PID-1 install traces, arm live fixes |
| **Injection test** | `iconia-injtest.c` | uinput event-injection probe |

## Notes carried forward

- `iconia-power-install.sh` binds the **AXP288** driver — that was the **wrong PMIC**
  (this board is Crystal Cove `INT33FD`). Kept as a documented dead end.
- The `*-deploy` / `*-arm*` scripts pushed live experiments before the fix was
  baked into the kernel config; on a new board prefer a kernel-config fragment once
  the fix is proven.
