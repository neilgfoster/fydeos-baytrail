# Bay Trail / Cherry Trail bring-up playbook

Distilled, board-agnostic lessons from the Acer Iconia W4-820 bring-up (24
sessions). Read this **before** starting a new Bay/Cherry Trail tablet — most of
these traps cost multiple sessions to diagnose the first time. Board-specific
detail and the full trail live in
[`../boards/iconia-w4-820/findings.md`](../boards/iconia-w4-820/findings.md) and its
[`hardware-status.md`](../boards/iconia-w4-820/hardware-status.md).

## The one problem this repo exists to solve

64-bit CPU + **32-bit-only UEFI**. Stock FydeOS ships a 64-bit GRUB and a kernel
built **without** `CONFIG_EFI_MIXED`, so the 32-bit firmware can't hand off to it.
Fix = add `bootia32.efi` **and** rebuild the openFyde kernel with `EFI_MIXED` so
`xloadflags` bit `0x04` (`XLF_EFI_HANDOVER_32`) is set. Check the stock kernel's
xloadflags first (`inspect-usb.sh`): `0x2b` means the bit is missing — that's the
whole blocker. Not for genuinely 32-bit CPUs (Clover Trail) — a 64-bit kernel
can't run at all there.

## Version-match the kernel to the userland

Build the kernel from the **same release branch** as the installer USB's userland
(`STOCK_KERNEL` → find its `release-Rxx-XXXXX.B-chromeos-6.6` branch). Version skew
(e.g. R138 kernel under R144 userland) causes subtle userspace crashes — it was
the multi-session red herring behind the ARC++ `run_oci` fault. Rebuild from the
**working** release config, not a drifted/hand-rolled minimal config.

## Boot-order & rootfs traps (each cost a session)

- **`depmod` after injecting modules.** A stale `modules.dep` with 0 entries for
  your new modules blocks udev from autoloading *anything* (WiFi/BT/audio/sensors
  all dead at once). Run `depmod -b <root> <uts>` after every module inject.
- **Decompress firmware if `CONFIG_FW_LOADER_COMPRESS` is off.** Firmware often
  ships only as `.xz`; `request_firmware(x.bin)` then fails `-2`. Decompress in
  place on the rootfs.
- **Early-coldplug modules must be real files on rootfs.** brcmfmac autoloads
  *before* stateful mounts — never symlink `/lib/modules` (or the running version
  subdir) into stateful, or WiFi dies on next boot. The 2.7 GB eMMC rootfs can't
  hold two full module trees; trim, don't symlink-all.
- **32-bit UEFI reads `<ESP>/boot/grub/grub.cfg`** (grub prefix), not
  `efi/boot/grub.cfg`. Edit the right one or your recovery entry won't appear.
- **ESP fill → truncated kernel copy → brick.** Free space + verify hash on every
  ESP kernel inject (see `iconia-esp-restore.sh`).

## Per-subsystem shortcuts

- **Display flicker:** `i915.enable_psr=0 enable_fbc=0 enable_dc=0` (cmdline only).
- **Backlight race:** intel_backlight can lose the probe race with the PMIC GPIO.
  Build `GPIO_CRYSTAL_COVE=y` (or your PMIC) built-in + the i915 EPROBE_DEFER-retry
  patch. Route brightness through powerd/`backlight_tool`, not raw sysfs, to keep
  the UI slider in sync.
- **Audio is the classic Bay Trail mess:** both legacy SST and SOF load, neither
  gets firmware. **Pick ONE** — legacy SST worked here (`snd_intel_dspcfg.dsp_driver=1`)
  with RT5640 + bytcr mach modules + a self-contained UCM. SOF playback was broken.
- **Buttons:** `INPUT_SOC_BUTTON_ARRAY=m` + `INTEL_INT0002_VGPIO=y` (power-wake).
  Driver names all nodes `gpio-keys` — match by capability, not name.
- **Auto-rotate:** full `HID_SENSOR_*=m` set + a panel-orientation quirk patch.
- **Bluetooth:** serdev core (`SERIAL_DEV_BUS=y` + `SERIAL_DEV_CTRL_TTYPORT=y`) +
  `SERIAL_8250_DW=m` + `BT_HCIUART/_BCM/_SERDEV=m`.
- **On-screen keyboard:** `--enable-virtual-keyboard` in `/etc/chrome_dev.conf`
  (tablet mode auto-hides it otherwise). Known bug: OSK dead on lock screen after
  idle — gates enabling idle auto-suspend.

## Known walls (don't sink time here)

- **PMIC identity first.** Crystal Cove (`INT33FD`) ≠ AXP288 (`INT33F4`). Binding
  the wrong charger/fuel-gauge driver wastes a session and fixes nothing. Mainline
  has **no Crystal Cove charger driver** → AC/charging bolt can't be fixed in
  software (only a DSDT `_PSR`/`_BST` override, not worth it).
- **Suspend:** many of these only expose s2idle (no deep S3) and resume is often
  broken. Disable idle-suspend (`disable_idle_suspend=1`); offer on-demand sleep
  via a button instead.
- **Cameras:** Bay Trail ISP (atomisp) is frequently BIOS function-disabled and
  locked, with no camera HAL anyway. Usually a write-off — confirm quickly, move on.
- **ARC++:** custom kernels lack ChromeOS alt-syscall → minijail `prctl(PR_ALT_SYSCALL)`
  fails → `run_oci` aborts. Either remove `"altSyscall":"android"` from the
  container `config.json`, or port the alt-syscall patch. It boots on-demand;
  idle teardown is normal, not a failure.

## Reusable assets

- Diagnostic scripts by category: [`diag/`](../diag/).
- Fix-location legend: [`hardware-status-legend.md`](hardware-status-legend.md).
- New-board procedure: [`adding-a-board.md`](adding-a-board.md).
