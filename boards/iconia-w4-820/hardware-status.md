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
| Backlight / brightness | ✅ works | i915 `intel_backlight` | kernel | Session 6 UPDATE: `/sys/class/backlight/intel_backlight` now present (max 100) and writes **visibly change the panel** — earlier "no backlight / Crystal Cove doesn't bind" note is SUPERSEDED: Crystal Cove **does** bind now (`byt_crystal_cove_pmic` + `crystal_cove_pwm` cells present). Caveat: out-of-band sysfs writes don't move the ChromeOS slider — route changes through powerd/`backlight_tool` to keep the UI in sync. Was sitting at 10/100 (low) in normal use. |
| Panel rotation | ❌ broken | `i915` `fbcon=rotate:` + userspace | cmdline + userspace | No auto-rotate at OOBE (session 2). Accel/IIO likely not up. Panel may be natively portrait. |
| Wi-Fi | ✅ works | `brcmfmac` SDIO, **BCM43241** (SDIO 02D0:4324) | rootfs (depmod+fw+nvram) | FIXED session 3: `depmod` (modules.dep had 0 brcmfmac — stale index blocked ALL module autoload) + decompress `brcmfmac43241b4-sdio.bin` (.xz unloadable, FW_LOADER_COMPRESS off) + NVRAM `brcmfmac43241b4-sdio.Acer-Iconia W4-820P.txt` (from VALLEYVIEW C0). Visible + connected. |
| Bluetooth | 🟡 partial | `btbcm` + `hci_uart`/serdev | kernel + firmware | Session 3: `bluetooth`+`btbcm` load, core inits, but NO hci0 — UART BT controller not instantiated. Needs serdev/`hci_uart` bind + `BCM-0bb4-0306.hcd` (present, .xz). Combo w/ BCM4324. |
| Audio | ❌ broken | contended: `intel_sst_acpi` vs `snd_sof` | kernel + **firmware+topology+UCM** | Session 3: BOTH legacy SST and SOF drivers load, neither gets firmware → no card. `fw_sst_0f28.bin` -2; SOF needs `sof-byt*.ri`+`.tplg`. Pick ONE stack, provide its fw/topology + ALSA UCM. Classic Bay Trail mess. |
| Touchscreen | ✅ works | I2C-HID (SYNA7300 / hid-multitouch) | kernel | Works out of the box at OOBE. |
| Accelerometer / sensors | ❌ broken | IIO (`kxcjk-1013`) / `SMO91D0` hub | kernel | Session 3: no IIO devices; `i2c-SMO91D0:00 can't add hid device -5`. Accel likely behind sensor hub / i2c_designware issue. |
| eMMC | ✅ works | `sdhci-acpi` + `I2C_DESIGNWARE_BAYTRAIL` | kernel | Reliable boot. Bay Trail rebuild booted first-try (i2c semaphore likely fixed enumeration). Still carries `sdhci.debug_quirks2=0x40` (HS200 off) in grub — test dropping it over more power-cycles. |
| microSD | untested | `sdhci-acpi` | kernel | |
| USB (OTG) | partial | `dwc3` / xhci | kernel | OTG adapter used to attach the installer USB. OTG keyboard input DEAD → no tablet terminal. |
| Battery level | ✅ works | ACPI `PNP0C0A` battery (`BATC`) | firmware/ACPI | Session 6: % is accurate & updates (watched it climb 98→100 on charge). Read via ACPI, not a PMIC driver. |
| Charging status / bolt | ❌ broken (firmware) | ACPI `ADP1` AC + `BATC` status | **firmware-limited** | Session 6: PMIC is **Crystal Cove** (`INT33FD`, NOT AXP288/`INT33F4`) — mainline has **no Crystal Cove charger driver**, so the `crystal_cove_charger`/`pwrsrc` MFD cells stay driver-less. Native `axp288_charger`/`fuel_gauge`/`extcon` were tried and are the WRONG chip (bind to nothing). Charging works physically, but ACPI `ADP1/online` is frozen `0` and `BATC/status` frozen `Discharging` even while plugged at 100% → ChromeOS shows no bolt. Only theoretical fix is a DSDT `_PSR`/`_BST` override. Parked. |
| Hardware buttons | ✅ works | `soc_button_array` (ACPI PNP0C40) | kernel | Session 5: `CONFIG_INPUT_SOC_BUTTON_ARRAY=m` (+ `INTEL_INT0002_VGPIO=y` for power-wake). Power/volume auto-adopted by ChromeOS; Windows/home = `KEY_LEFTMETA` (code 125). Driver names its nodes `gpio-keys` (x2) — match buttons by capability, not name. **Long-press Windows→crosh** via `install/iconia-buttond.c` (uinput injects Ctrl+Alt+T on ≥2s hold+release). |
| On-screen keyboard | ✅ works | ChromeOS virtual keyboard | rootfs (chrome_dev.conf) | Session 5: forced on with `--enable-virtual-keyboard` in `/etc/chrome_dev.conf` (tablet mode auto-hides it otherwise). Also lets a uinput keyboard coexist without suppressing the OSK. |
| Suspend (S0ix/S3) | ❌ broken → disabled | PM / ACPI (s2idle only) | powerd pref | Session 6: only `s2idle` exists (no S3 deep), resume broken (screen won't wake). powerd default would idle-suspend at 6m30s on battery → hang. Fixed by `disable_idle_suspend=1` (install/iconia-powertune) — screen still powers off on idle (saves power) but no broken auto-suspend. |
| Memory (2 GB) | ✅ tuned | zram/zstd + Chrome flags | tuning done | Session 7: zram lz4→zstd (3.7 GB) + swappiness=100/min_free=8192 (`install/iconia-memtune`); Chrome `--enable-low-end-device-mode`+`--renderer-process-limit=8` in chrome_dev.conf (site isolation kept) → avail ~863→1227 MB, procs 25→14. ARC not running (~28 MB stubs). |
| Power draw (idle) | ✅ optimal | RAPL / cpuidle | tuning done | Session 6: SoC `package-0`=~0.30W idle, C7S-dominant (deepest C-states already reached). Governor schedutil. Screen (dominant draw) now **adaptive** via ALS — see Backlight row. Meter: use RAPL (`intel-rapl:0/energy_uj`) for SoC A/B; battery gauge is 1%-quantized/freezes-at-100% (bad for fast A/B). Service/module trims = sub-noise power; done for RAM (~26MB) not watts. |
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
