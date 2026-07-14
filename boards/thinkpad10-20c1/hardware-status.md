# Hardware status matrix — Lenovo ThinkPad 10 20C1

Statuses: `untested` / `broken` / `partial` / `works`.
Fill in the driver from `dmesg` once booted. Fix-location legend is in
[../../docs/hardware-status-legend.md](../../docs/hardware-status-legend.md).

| Subsystem | Status | Driver / mechanism | Fix location | Notes |
|-----------|--------|--------------------|--------------|-------|
| Boot (EFI handover) | works | native 64-bit UEFI | n/a | no `EFI_MIXED`/`bootia32` needed (T1/T3) |
| Display / KMS | untested | | kernel/cmdline | |
| Backlight | untested | | kernel/cmdline | |
| Wi-Fi | untested (under FydeOS) | Broadcom SDIO `02D0:4324` (BCM43241), same chip as W4-820 | kernel + rootfs firmware | works under Windows today (channel #1) via `bcmdhd63.sys`/`43241b4rtecdc.bin`; see `iconia-wifi-fix.sh` for the known-good brcmfmac43241b4 recipe. **NVRAM/SROM note (T4):** neither Debian's `firmware-brcm80211` package nor this device's own Windows driver actually ships a `.txt` SROM file for this chip revision (`oem24.inf` references `bcm943241ipaagb_p100*.txt`, but no such file exists on the live filesystem - checked directly over SSH) - calibration appears to be embedded in the `43241b4rtecdc.bin`/`brcmfmac43241b4-sdio.bin` dongle image itself for this SKU. The rescue image (`rescue/`) ships the firmware `.bin` with no separate NVRAM; whether brcmfmac needs one anyway is unverified until the first real-hardware boot. |
| Bluetooth | untested | | kernel + firmware | |
| Audio | untested | | kernel + UCM (rootfs) | |
| Touchscreen | untested | | kernel + DMI/DSDT quirk | |
| Sensors | untested | | kernel | |
| eMMC | untested (under FydeOS) | `sdhci-acpi`, SanDisk SEM64G 58 GB | kernel | see PROGRESS.md T3 for full GPT layout |
| USB | **dead (confirmed, T3)** | xHCI controller healthy, port/traces physically dead | n/a — permanent, not kernel-fixable | folio keyboard (dock connector, separate from the dead host port) works fine over USB HID |
| Battery/PMIC | untested | | kernel | |
| Suspend | untested | Connected-Standby (S0ix only, no S3) | firmware-limited | |
