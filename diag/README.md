# Diagnostic toolkit (Bay Trail) — shared prior-art

These are the **one-off diagnostic, survey and probe scripts** first built while
bringing up the Acer Iconia W4-820. They are **not** part of any delivery build —
they inspect hardware, dump state, and A/B-test fixes. They live at the repo root
(not under `boards/`) because they are shared across boards: the *next* Bay Trail
tablet will need the same categories of probe, and this toolkit must **not** be
duplicated into every board dir.

The scripts are named `baytrail-*` by category. Their **contents** still carry
W4-820-specific detail (SSH IPs, i2c bus numbers, PMIC ACPI IDs, block devices) as
honest prior-art. For a new board, copy the relevant one, adjust those device
paths, and run it — don't expect it to work unmodified.

## By category

| Category | Scripts | What they check |
|----------|---------|-----------------|
| **General HW sweep** | `baytrail-hw-diag.sh` | one-shot dmesg / lspci / driver-bind survey |
| **Audio** | `baytrail-audio-diag.sh` | `/proc/asound/cards`, SST-vs-SOF, firmware `-2` errors, UCM |
| **Backlight** | `baytrail-backlight-diag.sh` | `/sys/class/backlight`, PMIC PWM cell binding |
| **WiFi** | `baytrail-wifi-diag.sh`, `baytrail-wifi99-diag.sh` | brcmfmac autoload, modules.dep, firmware/NVRAM presence |
| **Bluetooth** | `baytrail-bt-survey.sh`, `baytrail-bt-probe2.sh`, `baytrail-bt-deploy.sh`, `baytrail-bt-sco-*.sh`, `baytrail-btnmon.c` | serdev/UART bind, hci0, SCO routing, HCI monitor |
| **Sensors / accel** | `baytrail-sensor-diag.sh`, `baytrail-sensor-boot.sh`, `baytrail-sensor-load.sh`, `baytrail-emmc-sensor-check.sh`, `baytrail-emmc-armsensor.sh` | IIO devices, sensor-hub i2c, accel module load |
| **Power / battery** | `baytrail-power-diag.sh`, `baytrail-power-measure.sh`, `baytrail-power-install.sh`, `baytrail-pwr-rapl.sh`, `baytrail-pwr-sample.sh`, `baytrail-pwr-survey.sh`, `baytrail-batlog.sh` | RAPL draw, PMIC identity, AXP288-vs-Crystal-Cove (dead end), battery gauge |
| **Memory** | `baytrail-mem-survey.sh` | zram, swappiness, avail MB, Chrome proc count |
| **ESP / boot** | `baytrail-esp-diag.sh`, `baytrail-esp99-diag.sh` | ESP fill, kernel copy integrity, grub.cfg prefix |
| **eMMC / install debug** | `baytrail-emmc-debug.sh`, `baytrail-emmc-getlog.sh`, `baytrail-emmc-armaudio.sh` | pull PID-1 install traces, arm live fixes |
| **Injection test** | `baytrail-injtest.c` | uinput event-injection probe |

## Notes carried forward

- `baytrail-power-install.sh` binds the **AXP288** driver — that was the **wrong PMIC**
  (this board is Crystal Cove `INT33FD`). Kept as a documented dead end.
- The `*-deploy` / `*-arm*` scripts pushed live experiments before the fix was
  baked into the kernel config; on a new board prefer a kernel-config fragment once
  the fix is proven.
