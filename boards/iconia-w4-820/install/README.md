# Delivery build — Acer Iconia W4-820

**Status: DELIVERED + ARCHIVED (2026-07-11).** This is the final, reproducible
build for the W4-820. The physical unit's touchscreen is dead (dropped), so no
further on-hardware iteration is possible — this directory is frozen as the
reference implementation for future Bay Trail boards. See
[../hardware-status.md](../hardware-status.md) for the per-subsystem result matrix
and [../findings.md](../findings.md) for the full diagnostic trail.

Everything here **applies persistent fixes** to a real install. One-off probes,
surveys and superseded experiments were moved to the shared diagnostic toolkit at
[`../../_template/diag/`](../../_template/diag/).

---

## Final kernel

- **UTS release:** `6.6.99-g7232af57f054` (R144 build #4 baseline; later respins
  kept the same vermagic so `=m` modules still match).
- **Source branch:** `release-R144-16503.B-chromeos-6.6` (both Bay Trail patches
  apply clean; ashmem is native in 6.6.99 — no manual backport).
- **Why 6.6.99, not the R138/6.6.76 we started on:** committed in Session 19 to
  version-match the R144/16503 userland. See `../board.env` and PROGRESS S18–S19.

### Kernel config fragments (`../config/`, layered on `../../../config/efi-mixed.config`)

| Fragment | Purpose |
|----------|---------|
| `baytrail-hw.config`  | Bay Trail HW `=m` driver set: soc_button_array, RT5640 + bytcr mach + RL6231 (legacy SST audio), full HID-sensor set (auto-rotate), serdev + DW-UART + BT-HCIUART/BCM (Bluetooth). This fragment is what restored the 4 subsystems that regressed on the minimal 6.6.99 build. |
| `bluetooth-uart.config` | serdev core + `SERIAL_8250_DW` + BT UART stack (BCM2E3F → hci0). |
| `debug-console.config` | `console=tty1 earlycon loglevel=7` — kept in production on purpose (user wants visible boot activity). |
| `debug-capture.config` | boot-log capture helpers. |
| `trim.config` | drop unused drivers to fit the 2.7 GB eMMC rootfs. |
| `tpm.config` | TPM. |
| `axp288-power.config` | **DEAD END — do not enable.** This board is Crystal Cove (`INT33FD`), not AXP288. Kept only to document the wrong turn. |

### Kernel patches (`../patches/`)

| Patch | Purpose |
|-------|---------|
| `i915-dsi-pmic-gpio-defer-retry.patch` | i915 retries panel `gpiod_get` on `-EPROBE_DEFER`; fixes the intel_backlight registration race (gpio_crystalcove registers ~3 ms after i915 probes). Requires `CONFIG_GPIO_CRYSTAL_COVE=y` built-in. |
| `hid-accel-rotation.patch` | panel-orientation quirk so auto-rotate maps correctly in tablet mode. |
| `bt-sco-transport-routing.patch` | routes BT SCO (headset audio) over the correct transport. |

Grub cmdline extras baked into the final `../boot/grub.cfg`:
`i915.enable_psr=0 enable_fbc=0 enable_dc=0` (display flicker),
`snd_intel_dspcfg.dsp_driver=1` (force legacy SST — SOF playback is broken here),
`sdhci.debug_quirks2=0x40` (HS200 off → reliable eMMC).

---

## Install / finalize flow (keyboard-free, off the USB)

The tablet has no working local keyboard in FydeOS userspace, so install is driven
by PID-1 / `init=` wrappers launched from the installer USB, plus SSH for live
tweaks. Order:

1. **`iconia-install.sh`** (+ `iconia-install.conf`, or `iconia-init.sh` as a pure
   PID-1 variant) — install FydeOS to eMMC, then re-inject our `0x3f` kernel +
   `bootia32.efi` + `grub.cfg` (fixed PARTUUID) onto the eMMC ESP. Prints live to
   `/dev/tty1`.
2. **`iconia-emmc-finalize.sh`** — re-enable the UI (`ui.conf`) on the eMMC rootfs
   and tidy grub while keeping the boot console. Boots to OOBE.
3. **`iconia-wifi99-fix.sh`** — make the 6.6.99 module tree real on the rootfs +
   decompress `brcmfmac43241*` firmware + install NVRAM. WiFi must be a real file
   on rootfs (early coldplug, before stateful mounts). Enables SSH.
4. **`iconia-emmc-sshsetup.sh`** — pre-generate host keys + drop authorized_keys so
   we can SSH the running system (`ssh -i iconia_ed25519 root@…`).

Then the per-subsystem boot jobs (each idempotent, pushed over SSH; most take a
`revert` arg):

| Script | Installs | Subsystem |
|--------|----------|-----------|
| `iconia-buttons-install.sh` | soc_button_array enablement | HW buttons (volume, Windows key) |
| `iconia-buttond-install.sh` (+ `iconia-buttond.c/.conf`) | long-press-Windows → crosh uinput daemon | button UX |
| `iconia-accel-rotation-install.sh` | HID-sensor accel boot load | auto-rotate |
| `iconia-als-brightness-install.sh` | powerd ambient-light sensor wiring | adaptive brightness |
| `iconia-ucm-install.sh` | self-contained bytcr-rt5640 UCM + CRAS restart | audio |
| `iconia-memtune-install.sh` (+ `.conf/.sh`) | zram zstd + swappiness/min_free | 2 GB RAM |
| `iconia-chrome-memtune-install.sh` | low-RAM Chrome flags in chrome_dev.conf | 2 GB RAM |
| `iconia-powertune-install.sh` (+ `.conf/.sh`) | `disable_idle_suspend=1` + cpuidle | power / broken-suspend guard |
| `iconia-desktop-mode-install.sh` | FydeOS laptop/tablet toggle | UX |
| `iconia-shutdown-black-install.sh` (+ `.conf`) | black-at-shutdown Upstart job | shutdown fade |
| `iconia-acpoll-install.sh` (+ `.conf/.sh`) | power_supply UI-poke boot job | AC/battery UI (cosmetic; EC read is frozen — see note) |
| `iconia-binfmt-misc.conf` | binfmt_misc registration | ARC++ |

## Recovery scripts (keep — used if a build bricks)

- `iconia-modules-restore.sh` — restore `/lib/modules` onto eMMC rootfs (PID 1).
- `iconia-esp-restore.sh` — rebuild the ESP after an ESP-full truncated-kernel event.
- `iconia-fixboot.sh` — make the eMMC bootable via firmware NVRAM after install.
- `iconia-kernel-reinject.sh` — re-inject a rebuilt kernel + modules to eMMC.
- `iconia-wifi-fix.sh` — 6.6.76-era WiFi fix, superseded by `iconia-wifi99-fix.sh`;
  kept for the depmod/firmware-decompress recipe it documents.

---

## Known-limited / accepted (documented, not fixed)

- **AC / charging bolt** — Crystal Cove has no mainline charger driver; on 6.6.99
  the i2c-0 EC read also freezes, so `ADP1/online` and `BATC/status` are stale.
  Charging works physically. `iconia-acpoll` only pokes the UI. Accepted.
- **Suspend (S3)** — no deep S3; s2idle resume was unreliable, so idle-suspend is
  disabled. On-demand sleep ships via double-tap-Windows → `powerd_dbus_suspend`.
- **Cameras** — Bay Trail ISP is BIOS function-disabled + locked. Not feasible.
- **Android/ARC++** — boots to system_server after removing `"altSyscall":"android"`
  from the container config (custom kernel lacks ChromeOS alt-syscall). Left as a
  config edit, not baked into the kernel.
