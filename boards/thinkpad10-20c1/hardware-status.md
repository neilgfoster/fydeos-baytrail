# Hardware status matrix — Lenovo ThinkPad 10 20C1

Statuses: `untested` / `broken` / `partial` / `works`.
Fill in the driver from `dmesg` once booted. Fix-location legend is in
[../../docs/hardware-status-legend.md](../../docs/hardware-status-legend.md).

**T5 (2026-07-14): full Windows device/firmware catalogue done** while channel #1 is
still the intact reference — read-only, no risk to SSH. Raw PnP inventory, BIOS/board
info, and pulled+verified firmware/calibration blobs are in
[`reference/`](reference/) (see `reference/README.md`). Details below fold into each
row; anything not yet reflected in a driver name is still to be matched against the
upstream Linux driver during bring-up.

| Subsystem | Status | Driver / mechanism | Fix location | Notes |
|-----------|--------|--------------------|--------------|-------|
| Boot (EFI handover) | works | native 64-bit UEFI | n/a | no `EFI_MIXED`/`bootia32` needed (T1/T3) |
| Display / KMS | untested | | kernel/cmdline | |
| Backlight | untested | | kernel/cmdline | |
| Wi-Fi | untested (under FydeOS) | Broadcom SDIO `02D0:4324` (BCM43241), same chip as W4-820 | kernel + rootfs firmware | works under Windows today (channel #1) via `bcmdhd63.sys`/`43241b4rtecdc.bin`; see `iconia-wifi-fix.sh` for the known-good brcmfmac43241b4 recipe. **NVRAM/SROM note (T4):** neither Debian's `firmware-brcm80211` package nor this device's own Windows driver actually ships a `.txt` SROM file for this chip revision (`oem24.inf` references `bcm943241ipaagb_p100*.txt`, but no such file exists on the live filesystem - checked directly over SSH) - calibration appears to be embedded in the `43241b4rtecdc.bin`/`brcmfmac43241b4-sdio.bin` dongle image itself for this SKU. The rescue image (`rescue/`) ships the firmware `.bin` with no separate NVRAM; whether brcmfmac needs one anyway is unverified until the first real-hardware boot. **T5:** exact `43241b4rtecdc.bin` (405,555 bytes) pulled from the live Windows driver store and byte-verified against `Get-Item`'s reported length; saved at `reference/firmware/wifi/`. Confirms the "no separate NVRAM" finding — the matching `bcmdhd.inf_amd64_2a6609548a4c11d4` package ships only this one `.bin`, nothing else. |
| Bluetooth | untested | Broadcom BCM43241B0 (same combo chip as Wi-Fi), enumerates over UART via `BtwSerialBus` (ACPI `BCM2E55`), not the SDIO fn2 path | kernel + firmware | **T5 find:** patchram firmware `BCM43241B0_002.001.013.0073.0076.hcd` pulled from `btwserialbus.inf` package and saved at `reference/firmware/bluetooth/` (15,739 bytes, verified). `.hcd` is the standard format Linux's `hci_uart`/`btbcm` (`brcm_patchram_plus`-style) BT loading expects — this is the concrete artifact that was missing before; previously this row had nothing to go on. |
| Audio | untested | Realtek ALC5640/RT5640 I2S codec, ACPI `10EC5640` (`rtii2sac.sys`) | kernel + UCM (rootfs) | **T5:** confirmed no separate firmware blob — package only ships the Windows codec driver/service binaries, no `.bin`. Matches expectation for this codec family; Linux side needs an ASoC machine driver + UCM profile, not a firmware file. |
| Touchscreen | untested | Atmel, generic HID-over-I2C (`HID\VEN_ATML&DEV_1000`, driven by in-box `hidi2c.inf`, no vendor package) | kernel + DMI/DSDT quirk | **T5:** confirmed no dedicated vendor driver/firmware exists at all — Windows uses its native HID-I2C stack. Good news for Linux: `i2c-hid` + `hid-multitouch` is the expected path, no firmware to source. |
| Sensors | untested | IMU: InvenSense MPU-6500 (`HID\INV6500`, HID sensor collection); GNSS: Broadcom BCM4752 (`ACPI\LNV4752`, `BcmGnssBus.sys`) | kernel | **T5:** both chips identified for the first time (previously blank). No firmware blob found for either (GNSS package ships only the bus driver `.sys`); IMU is standard HID sensor, likely usable via in-kernel `hid-sensor-hub` + `inv_mpu6050` route. |
| NFC | untested | Broadcom BCM2079x (`ACPI\BCM2F1F`, `BcmNfcIc.sys`) | kernel + firmware | **New row, T5.** Not previously tracked. 5 `.ncd` firmware variants (BCM20791B4/B5, several sub-revisions) pulled to `reference/firmware/nfc/` — exact revision needed by this device's silicon not yet narrowed down; low priority unless NFC use is wanted. |
| Cellular / WWAN | untested | Sierra Wireless EM7345 4G LTE (`USB\VID_1199&PID_A001`), Microsoft in-box MBIM stack (`netvwwanmp.inf`) | kernel (cdc_mbim/qmi_wwan) | **New row, T5.** Device has a WWAN modem, not previously noted at all. Modem firmware lives on the module itself, not extractable/needed from Windows — Linux would use standard `cdc_mbim`. Low priority unless mobile broadband is wanted. |
| Cameras | untested | Front: OV2722 (`ACPI\INT33FB`); Rear: Sony IMX175 (`ACPI\INTCF1A`), both via Intel `atomisp` | kernel (atomisp, notoriously unmaintained on Linux) | **New row, T5.** Per-sensor `.cpf` calibration blobs pulled to `reference/firmware/camera/` (byte-verified) in case an atomisp attempt is ever made; camera support on Bay Trail Linux is a known long-standing dead end (see Iconia W4-820 archived board section), so this is speculative/low-priority. |
| Fingerprint | n/a | Synaptics VFS6101 (`ACPI\VFSI6101`) | — | **New row, T5.** Present on this device; no dedicated driver package found in the Windows driver store (uses the generic biometric framework class driver) and no known upstream Linux support for this sensor — treating as unsupportable, not pursuing. |
| eMMC | untested (under FydeOS) | `sdhci-acpi`, SanDisk SEM64G 58 GB | kernel | see PROGRESS.md T3 for full GPT layout |
| USB | **dead (confirmed, T3)** | xHCI controller healthy, port/traces physically dead | n/a — permanent, not kernel-fixable | folio keyboard (dock connector, separate from the dead host port) works fine over USB HID |
| Battery/PMIC | untested | | kernel | |
| Suspend | untested | Connected-Standby (S0ix only, no S3) | firmware-limited | |
