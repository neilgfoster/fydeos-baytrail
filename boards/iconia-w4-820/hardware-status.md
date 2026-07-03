# Hardware status matrix — Acer Iconia W4-820 (Bay Trail-T)

Track each subsystem across sessions. Update **Status** as we test on hardware.
Statuses: `untested` / `broken` / `partial` / `works`.

> **Session 3 key insight — a stale `modules.dep` was blocking ALL module autoload.**
> After injecting the 6.6.76 modules we never ran `depmod`, so `modules.dep`/`.alias`
> had 0 brcmfmac entries → udev couldn't autoload *any* module (WiFi/BT/audio/sensors).
> Also `CONFIG_FW_LOADER_COMPRESS` is unset but firmware ships only as `.xz`, so
> `request_firmware(<name>.bin)` fails -2. **General fix pattern for module-based HW:**
> `depmod -b <root> 6.6.76-gabcfb16364e1` + decompress the needed `/lib/firmware/*.xz`
> in place (+ board NVRAM where needed). Done on eMMC ROOT-A by `iconia-wifi-fix.sh`.
> Re-test BT/audio/sensors now that autoload works and audio fw was decompressed.

SoC: Intel Atom **Z3740D** (Bay Trail-T, Gen7 iGPU). Firmware: 32-bit UEFI, no CSM.

| Subsystem | Status | Likely driver / mechanism | Fix location | Notes |
|-----------|--------|---------------------------|--------------|-------|
| Boot (EFI handover) | ✅ works | `CONFIG_EFI_MIXED` + handover proto | **kernel** | xloadflags 0x3f; boots to OOBE. |
| Display / KMS | ✅ works | `i915` (Gen7 Valleyview) | kernel cfg + **cmdline** | Flicker FIXED via `i915.enable_psr=0 enable_fbc=0 enable_dc=0` (confirmed session 2). Smooth. |
| Backlight / brightness | ❌ broken | `intel_backlight` / ACPI | kernel + **cmdline** | Brightness control does nothing at OOBE (session 2). Try `acpi_backlight=native|vendor`, `i915.enable_dpcd_backlight=1`. |
| Panel rotation | ❌ broken | `i915` `fbcon=rotate:` + userspace | cmdline + userspace | No auto-rotate at OOBE (session 2). Accel/IIO likely not up. Panel may be natively portrait. |
| Wi-Fi | ✅ works | `brcmfmac` SDIO, **BCM43241** (SDIO 02D0:4324) | rootfs (depmod+fw+nvram) | FIXED session 3: `depmod` (modules.dep had 0 brcmfmac — stale index blocked ALL module autoload) + decompress `brcmfmac43241b4-sdio.bin` (.xz unloadable, FW_LOADER_COMPRESS off) + NVRAM `brcmfmac43241b4-sdio.Acer-Iconia W4-820P.txt` (from VALLEYVIEW C0). Visible + connected. |
| Bluetooth | untested | `btbcm` / `hci_uart` | kernel + firmware | Paired with the Wi-Fi combo chip. |
| Audio | ❌ broken | `intel_sst` `bytcr_rt5640` | kernel + **firmware (rootfs)** | No sound at OOBE (session 2). `fw_sst_0f28.bin` failed to load (-2); No soundcards found. Needs firmware + UCM. |
| Touchscreen | ✅ works | I2C-HID (SYNA7300 / hid-multitouch) | kernel | Works out of the box at OOBE. |
| Accelerometer / sensors | ❌ broken | IIO (`kxcjk-1013` etc.) | kernel | No auto-rotate (session 2) → sensors likely absent. Check `dmesg`/`/sys/bus/iio`. |
| eMMC | works (installer) | `sdhci-acpi` | kernel | Installer already reads/writes it. |
| microSD | untested | `sdhci-acpi` | kernel | |
| USB (OTG) | partial | `dwc3` / xhci | kernel | OTG adapter used to attach the installer USB. OTG keyboard input DEAD → no tablet terminal. |
| Battery / charging | partial | `axp288` PMIC + fuel gauge | kernel | Reports 100% at OOBE (session 2) — fuel gauge reads. Charging behaviour untested. |
| Suspend (S0ix/S3) | untested | PM / ACPI | **firmware-limited** | Often half-broken on Bay Trail; may not be fixable. |
| Cameras | untested | atomisp / uvc | kernel + firmware | atomisp is notoriously painful; may be a write-off. |

## Fix-location legend

- **kernel** — `CONFIG_*` change → rebuild `chromeos-kernel-6_6` → re-inject `vmlinuz`
  (same flow as the EFI_MIXED fix). Add fragments alongside `config/efi-mixed.config`.
- **cmdline** — kernel parameter only. Edit the injected `/boot/grub/grub.cfg`
  `linux` line — **no rebuild needed**. Fastest iteration; try these first.
- **firmware/rootfs** — blobs (`/lib/firmware`) or ALSA UCM (`/usr/share/alsa`) live
  on the rootfs, not the kernel. Use `scripts/inject-rootfs.sh`.
- **DMI/DSDT quirk** — a kernel patch matching this board (see `patches/`), or a
  DSDT override supplied at boot.
- **firmware-limited** — lives in the 32-bit UEFI; kernel can only work around, not
  fix. Suspend and some ACPI bugs fall here.

## Method for adding a fix

1. Reproduce/confirm the failure; note the driver from `dmesg` once booted.
2. Decide the fix location from the table above.
3. cmdline → edit grub.cfg and reboot. kernel → add a `config/*.config` fragment
   and/or a `patches/*.patch`, rebuild, re-inject. rootfs → drop files via
   `inject-rootfs.sh`.
4. Record the result and the exact change in this table + a line in `PROGRESS.md`.
