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
| Wi-Fi | ✅ works | `brcmfmac` SDIO, **BCM43241** (SDIO 02D0:4324) | rootfs (depmod+fw+nvram) | FIXED session 3: `depmod` (modules.dep had 0 brcmfmac — stale index blocked ALL module autoload) + decompress `brcmfmac43241b4-sdio.bin` (.xz unloadable, FW_LOADER_COMPRESS off) + NVRAM `brcmfmac43241b4-sdio.Acer-Iconia W4-820P.txt` (from VALLEYVIEW C0). Visible + connected. **S17 caution:** brcmfmac autoloads during **early coldplug BEFORE stateful mounts**, so its `.ko` MUST be a real file on the rootfs — making `/lib/modules` (or the running kernel's version subdir) a symlink into stateful breaks WiFi on the next boot (dangling target at coldplug). Recovered via `install/iconia-modules-restore.sh`. |
| Bluetooth | 🟡 partial | `btbcm` + `hci_uart`/serdev | kernel + firmware | Session 3: `bluetooth`+`btbcm` load, core inits, but NO hci0 — UART BT controller not instantiated. Needs serdev/`hci_uart` bind + `BCM-0bb4-0306.hcd` (present, .xz). Combo w/ BCM4324. |
| Audio | ❌ broken | contended: `intel_sst_acpi` vs `snd_sof` | kernel + **firmware+topology+UCM** | Session 3: BOTH legacy SST and SOF drivers load, neither gets firmware → no card. `fw_sst_0f28.bin` -2; SOF needs `sof-byt*.ri`+`.tplg`. Pick ONE stack, provide its fw/topology + ALSA UCM. Classic Bay Trail mess. |
| Touchscreen | ✅ works | I2C-HID (SYNA7300 / hid-multitouch) | kernel | Works out of the box at OOBE. |
| Accelerometer / sensors | ❌ broken | IIO (`kxcjk-1013`) / `SMO91D0` hub | kernel | Session 3: no IIO devices; `i2c-SMO91D0:00 can't add hid device -5`. Accel likely behind sensor hub / i2c_designware issue. |
| eMMC | ✅ works | `sdhci-acpi` + `I2C_DESIGNWARE_BAYTRAIL` | kernel | Reliable boot. Bay Trail rebuild booted first-try (i2c semaphore likely fixed enumeration). Still carries `sdhci.debug_quirks2=0x40` (HS200 off) in grub — test dropping it over more power-cycles. |
| microSD | ✅ works | `sdhci-acpi` | kernel | Tested working (session 10, 2026-07-05). |
| USB (OTG) | partial | `dwc3` / xhci | kernel | OTG adapter used to attach the installer USB. S16: an **OTG keyboard DOES work at the grub menu / firmware level** (used it to select a kernel entry during recovery) — earlier "OTG keyboard input DEAD" refers to FydeOS *userspace* (no tablet terminal). Keyboard-at-grub lifts the "no keyboard" recovery constraint. **S17 USB-recovery gotcha:** this tablet is **32-bit UEFI → boots `efi/boot/bootia32.efi`, which reads `<ESP>/boot/grub/grub.cfg`** (grub prefix), NOT `efi/boot/grub.cfg`. Edit `/boot/grub/grub.cfg` on the USB ESP or the recovery entry won't appear. Recovery USB = `/dev/sda` (ROOT-A `sda3`, ESP `sda12`); PID-1 scripts go in ROOT-A `/sbin`. |
| Battery level | ✅ works | ACPI `PNP0C0A` battery (`BATC`) | firmware/ACPI | Session 6: % is accurate & updates (watched it climb 98→100 on charge). Read via ACPI, not a PMIC driver. |
| Charging status / bolt | ❌ broken (firmware) | ACPI `ADP1` AC + `BATC` status | **firmware-limited** | Session 6: PMIC is **Crystal Cove** (`INT33FD`, NOT AXP288/`INT33F4`) — mainline has **no Crystal Cove charger driver**, so the `crystal_cove_charger`/`pwrsrc` MFD cells stay driver-less. Native `axp288_charger`/`fuel_gauge`/`extcon` were tried and are the WRONG chip (bind to nothing). Charging works physically, but ACPI `ADP1/online` is frozen `0` and `BATC/status` frozen `Discharging` even while plugged at 100% → ChromeOS shows no bolt. Only theoretical fix is a DSDT `_PSR`/`_BST` override. Parked. |
| Hardware buttons | ✅ works | `soc_button_array` (ACPI PNP0C40) | kernel | Session 5: `CONFIG_INPUT_SOC_BUTTON_ARRAY=m` (+ `INTEL_INT0002_VGPIO=y` for power-wake). Power/volume auto-adopted by ChromeOS; Windows/home = `KEY_LEFTMETA` (code 125). Driver names its nodes `gpio-keys` (x2) — match buttons by capability, not name. **Long-press Windows→crosh** via `install/iconia-buttond.c` (uinput injects Ctrl+Alt+T on ≥2s hold+release). |
| On-screen keyboard | ✅ works | ChromeOS virtual keyboard | rootfs (chrome_dev.conf) | Session 5: forced on with `--enable-virtual-keyboard` in `/etc/chrome_dev.conf` (tablet mode auto-hides it otherwise). Also lets a uinput keyboard coexist without suppressing the OSK. |
| Suspend (S0ix/S3) | ❌ broken → disabled | PM / ACPI (s2idle only) | powerd pref | Session 6: only `s2idle` exists (no S3 deep), resume broken (screen won't wake). powerd default would idle-suspend at 6m30s on battery → hang. Fixed by `disable_idle_suspend=1` (install/iconia-powertune) — screen still powers off on idle (saves power) but no broken auto-suspend. |
| Memory (2 GB) | ✅ tuned | zram/zstd + Chrome flags | tuning done | Session 7: zram lz4→zstd (3.7 GB) + swappiness=100/min_free=8192 (`install/iconia-memtune`); Chrome `--enable-low-end-device-mode`+`--renderer-process-limit=8` in chrome_dev.conf (site isolation kept) → avail ~863→1227 MB, procs 25→14. ARC not running (~28 MB stubs). |
| Power draw (idle) | ✅ optimal | RAPL / cpuidle | tuning done | Session 6: SoC `package-0`=~0.30W idle, C7S-dominant (deepest C-states already reached). Governor schedutil. Screen (dominant draw) now **adaptive** via ALS — see Backlight row. Meter: use RAPL (`intel-rapl:0/energy_uj`) for SoC A/B; battery gauge is 1%-quantized/freezes-at-100% (bad for fast A/B). Service/module trims = sub-noise power; done for RAM (~26MB) not watts. |
| Cameras | untested | atomisp / uvc | kernel + firmware | atomisp is notoriously painful; may be a write-off. |
| Android / ARC++ | 🟡 blocked (kernel version skew) | legacy ARC++ container (`run_oci`) | **kernel version** | S16 TRUE root cause: ARC boots **on-demand** but `run_oci` **SIGSEGVs** (GP fault in libc, android-uid child) on the custom **6.6.76 (R138)** kernel under the **6.6.99 (R144/16503) userland** → mini-container crashes ~250ms in → the Play/opt-in wizard spins. Overlay `chromiumos.allow_overlayfs` (S15) + ashmem still valid; binfmt_misc/houdini/25s-timeout (S15 layers 3–4) were WRONG. FIX = version-matched **6.6.99** kernel from the OPEN `release-R144-16503.B-chromeos-6.6` (both Bay-Trail patches apply clean; drop manual ashmem — native in 6.6.99). bzImage BUILT (`6.6.99-g7232af57f054`). **S17: modules deployed (366 .ko, staged on stateful) → R144 now BOOTS to login on Bay Trail** (the bootloop was purely missing modules). ARC-on-6.6.99 **not yet validated**: WiFi is down on 6.6.99 (needed for SSH + opt-in) — likely the brcmfmac firmware rev (6.6.99 driver lists `…43241b5-sdio.bin`; only b4 decompressed) and/or early-autoload timing of the stateful-symlinked 6.6.99 tree. Reverted to 6.6.76 for now. Reference: crosh laptop (same slim-io/16503) runs ARC fine on stock `6.6.99-fyde`. Play Store = OpenGApps add-on (a re-flash corrupted `/system` → reverted). Detail: PROGRESS S16/S17 + memory `iconia-android-arc-diag`. |

## Session 18 (2026-07-09) — verification on the 6.6.99 (R144) kernel

We migrated the tablet to the version-matched **6.6.99-g7232af57f054** kernel (WiFi-on-6.6.99
fixed — the 6.6.99 module tree is now REAL on the rootfs; see PROGRESS S18 + memory
`iconia-kernel-config-baseline`). Status of each subsystem **on 6.6.99** vs how it was on 6.6.76:

| Subsystem | 6.6.76 | **6.6.99** | Why changed / how to restore |
|-----------|--------|-----------|------------------------------|
| Boot / eMMC / display-lit | ✅ | ✅ works | i915=y built-in; boots to login. |
| WiFi (brcmfmac) | ✅ | ✅ works | Fixed: 6.6.99 tree made real on rootfs (early coldplug). |
| SSH (iconia-debug key) | ✅ | ✅ works | authorized_keys on ROOT-A; connect `ssh -i iconia_ed25519`. |
| Touchscreen | ✅ | ✅ works | I2C-HID built-in (input event2 / SYNA). |
| microSD | ✅ | ✅ works | mmcblk1 auto-mounts. |
| Battery % | ✅ | ✅ works | ACPI BATC (95%). |
| On-screen keyboard | ✅ | ✅ works | rootfs `/etc/chrome_dev.conf` (kernel-independent). |
| Suspend-disable (idle) | ✅ | ✅ works | powerd `disable_idle_suspend=1` persisted. |
| zram (swap active) | ✅ tuned | ⚠️ **active but UNtuned** | zram up but **lz4 / swappiness 60** — our zstd + swappiness 100 + min_free (`iconia-memtune`) is a **live-only** tweak, not re-applied after reboot. Re-run memtune / bake it. |
| **Backlight / brightness** | ✅ | ❌ **REGRESSED** | `/sys/class/backlight/` is EMPTY on 6.6.99 (panel is lit at default, but no control node → no ALS/adaptive brightness). intel_backlight not registering — investigate config delta / PMIC PWM cell. |
| **Audio** | ✅ (UCM) | ❌ **REGRESSED** | `/proc/asound/cards` = no cards. Audio drivers not autoloading on 6.6.99 (built from minimal working.config; the RT5640/SOF `=m` drivers 6.6.76 had aren't in the 6.6.99 set). UCM still on rootfs. |
| **Hardware buttons** | ✅ | ❌ **REGRESSED** | `soc_button_array` not loaded (no gpio-keys nodes) → volume + Windows→crosh dead. Power works (firmware). Module missing from 6.6.99 set. |
| **Auto-rotate** | ✅ | ❌ **REGRESSED** | No IIO devices; **`hid-sensor-accel-3d.ko` not built for 6.6.99 vermagic**. Panel-orientation quirk is built-in (patch), but the accel module is absent. |
| Bluetooth | 🟡 partial | ❌ broken | No hci; BT `=m` modules (`hci_uart`/`btbcm`) not in 6.6.99 set (was only partial on 6.6.76 too). |
| **Android / ARC++** | 🟡 blocked | ❌ **still broken — theory disproven** | `run_oci` **STILL `#GP`-faults in libc** on the version-matched 6.6.99 kernel → **kernel version skew was NOT the root cause**. Deterministic `#GP` at libc `+0x8d7` on Bay Trail (Silvermont; CPU flags show only `smep`, no smap/avx/xsave/fsgsbase). New lead = CPU-instruction/feature incompatibility in run_oci's post-`unshare` child (tablet-specific; the "working" reference laptop is a newer CPU). Minidump saved (`/home/chronos/crash/run_oci.*.dmp`) — decode the faulting instruction next. Also seen: arc-setup `Owner uid 0 instead of 603/655360` (overlay ownership residue) + `arcbootcontinue exit 1`. |

**Root remedy for most 6.6.99 regressions:** the 6.6.99 modules were built from minimal
`working.config`, so the `=m` drivers 6.6.76 carried (soc_button_array, snd/RT5640/SOF audio,
hid-sensor-accel-3d, backlight, BT) are absent. **Rebuild the 6.6.99 module set from the FULL
6.6.76 driver config (port the `=m` set), redeploy → restores buttons+audio+rotate+backlight+BT
in one shot.** Then re-apply/bake the live tweaks (memtune). See PROGRESS S18 next-session plan.

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
