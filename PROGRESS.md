# PROGRESS — session log & resume guide

> **Read this first when resuming.** This is a multi-session project. This file is
> the source of truth for *where we are*, *what's decided*, and *what's next*.
> Update the "Current state" and "Next actions" sections at the end of each session.

## Goal

A repeatable process to boot & install FydeOS/openFyde on an **Acer Iconia W4-820**
(64-bit Bay Trail CPU, **32-bit UEFI** firmware):

1. **inspect** a stock FydeOS installer USB → kernel version, `xloadflags`, cmdlines.
2. **build** a custom openFyde kernel with `CONFIG_EFI_MIXED` (adds the 32-bit EFI
   handover entry the stock kernel lacks).
3. **inject** the kernel + `bootia32.efi` + clean `grub.cfg` back onto the USB, boot,
   then install to eMMC.

## Environment facts (so we don't re-derive them)

- Work happens from a **FydeOS device** running a **Crostini** (Debian 12) container.
- The Crostini container is the build host: **~120 GB free disk, 29 GB RAM, 8 CPU** —
  enough for a kernel-only openFyde build. `gh` is authed as `neilgfoster`.
- The installer USB is **only visible to the ChromeOS/crosh host**, not to Crostini.
  So: `inspect`/`inject` run in **crosh `shell`**; `build` runs in **Crostini**.
- In crosh, the USB enumerates as `sd?` and moves letters between replugs
  (seen as both `sda` and `sdb`). The ESP is **partition 12** (32M FAT).

## Key technical fact (the crux)

`xloadflags` @ offset `0x236` of the kernel image. Bit `0x04` = `XLF_EFI_HANDOVER_32`.
- Stock FydeOS kernel = **`0x2b`** → bit CLEAR → **won't boot** on 32-bit UEFI.
- Need a rebuild reading **`0x2f`** (bit set). This one byte is the go/no-go test.

Full reasoning: [`boards/iconia-w4-820/findings.md`](boards/iconia-w4-820/findings.md).

## Milestones

| # | Milestone | State |
|---|-----------|-------|
| 1 | Confirm USB is 64-bit-UEFI-only | ✅ done |
| 2 | Add `bootia32.efi` + clean grub.cfg; reach GRUB on tablet | ✅ done |
| 3 | Diagnose kernel freeze → missing `XLF_EFI_HANDOVER_32` (`0x2b`) | ✅ done |
| 4 | Scaffold repo + inspect/inject/build scripts | ✅ done |
| 5 | Sync openFyde, pin board + kernel package + config path | 🟡 kernel ver pinned (6.6.99-fyde); tree not synced |
| 6 | Build kernel with EFI_MIXED; verify handover bit | ✅ done — **`xloadflags=0x3f`** (6.6.76, trimmed) |
| 7 | Inject to USB; boot tablet past the freeze | ✅ **DONE** — kernel boots to userspace (init=/bin/sh) |
| 7b | FydeOS userspace boots (real init) | ✅ **DONE** — boots to OOBE, touchscreen works! |
| 8 | Install to eMMC; re-inject kernel+modules to eMMC; standalone boot | ✅ DONE — eMMC boots FydeOS to OOBE standalone (USB removed) |

## Open questions / unknowns to resolve

- **openFyde manifest branch** to pin (`MANIFEST_BRANCH`) — match the kernel version
  the installer USB actually ships (get it from `inspect-usb.sh` → `KVER_A`).
- **Exact board name**: `amd64-generic` vs a FydeOS-specific board (USB label was
  `amd64-fydeos_slim`). Confirm in the synced tree.
- **Kernel package name** (`chromeos-kernel-<ver>`) and the **config fragment path**
  under `src/third_party/kernel/v*/chromeos/config/`. `build-kernel.sh config`
  auto-discovers these into `build.env`; verify them.
- Whether `cros_sdk` runs cleanly inside Crostini (mount/namespace ok — `unshare`
  test passed — but the SDK chroot may need more).

## Current state (update me each session)

- **As of:** 2026-07-01
- Repo scaffolded; scripts written. **Inspection RUN against real USB** →
  results captured in [`boards/iconia-w4-820/usb-profile.env`](boards/iconia-w4-820/usb-profile.env).
- **Installer kernel = `6.6.99-fyde-09011-gfdc62122de5f-dirty`, built 2025-12-15.**
  Confirmed `xloadflags=0x2b` (no 32-bit handover) on both A and B slots.
- `bootia32.efi` + `grub.cfg` were manually placed on the USB earlier and confirmed
  to reach the kernel-handoff freeze. `inject-kernel.sh` reproduces that placement.
- **Repo restructured multi-board**: shared machinery (`scripts/`, `config/efi-mixed.config`,
  `docs/`) + per-device `boards/<id>/` (W4-820 = `boards/iconia-w4-820/`). All scripts
  take `--board <id>`. New devices: `docs/adding-a-board.md`, `boards/_template/`.
- **ABANDONED the full `repo sync` approach.** It pulled ~94G of the ChromiumOS
  tree (to build ONE kernel), the Chromium browser project had a bad ref
  (`openfyde-r138-dev` missing) that aborted the sync before the kernel checkout,
  and the working-tree checkout **filled the 128G disk to 100%**. Killed it and
  `rm -rf`'d `~/openfyde/src` → back to 117G free.
- **PIVOT WORKED: minimal standalone kernel build (Option A).** No `cros_sdk`, no
  94G tree — just the kernel git (1.8G) built with plain `make`. Steps that worked:
  1. `git clone --depth 1 --single-branch -b release-R138-16295.B-chromeos-6.6`
     `https://chromium.googlesource.com/chromiumos/third_party/kernel ~/openfyde/kernel-6.6`
     → 1.8G, 84k files, includes `chromeos/scripts/prepareconfig`. **Kernel = 6.6.76**
     (note: USB shipped 6.6.99-fyde — sublevel mismatch; modules won't match, OK for
     boot test; revisit r144-dev if we need 6.6.99).
  2. `CHROMEOS_KERNEL_FAMILY=chromeos chromeos/scripts/prepareconfig chromiumos-x86_64-generic`
     (the flavour the openFyde amd64 board uses; only the `reven`/ChromeOS-Flex
     flavour ships EFI_MIXED by default — confirms why stock was 0x2b).
  3. Append `config/efi-mixed.config` (EFI_MIXED + HANDOVER_PROTOCOL + STUB) to `.config`.
  4. `make olddefconfig` → **all three survived** (verified in expanded 7908-line config).
  5. Toolchain: **plain gcc works** (no CLANG/CFI/LTO forcing in this config). Installed
     `build-essential bc bison flex libssl-dev libelf-dev cpio kmod rsync`.
  6. Applied `boards/iconia-w4-820/config/trim.config` (drop nouveau/media/virtio-gpu/
     infiniband) to cut build time; essentials + EFI_MIXED verified intact.
  7. `make -j8 bzImage` (gcc) → **SUCCESS**. `arch/x86/boot/bzImage` = 10.3MB,
     **`xloadflags=0x3f` (HANDOVER32 SET)** vs stock `0x2b`. Version
     `6.6.76-gabcfb16364e1 #2`. Copied to `boards/iconia-w4-820/out/vmlinuz` and
     published as GitHub release asset `kernel-6.6.76-efimixed`.
  Build host: `~/openfyde/kernel-6.6`. Logs: `~/openfyde/logs/`. Build ~15 min trimmed.
  NOTE: version `6.6.76` (no `-fyde`) ≠ rootfs modules `6.6.99-fyde` → modules won't
  load; fine for boot test (essentials built-in). Revisit for full HW support.

## Build target — PINNED

openFyde layers on the **upstream ChromiumOS manifest** via `local_manifests`
(NOT a direct init of the openFyde manifest — that only has 21 overlay projects):

```
repo init -u https://chromium.googlesource.com/chromiumos/manifest.git \
  --repo-url https://chromium.googlesource.com/external/repo.git \
  -b release-R138-16295.B
git clone https://github.com/openFyde/manifest.git openfyde/manifest -b r138-dev
ln -snfr openfyde/manifest .repo/local_manifests
repo sync -j"$(nproc)"
```

- **ChromiumOS release: `release-R138-16295.B`** (upstream base).
- **openFyde manifest branch: `r138-dev`** — overlays via local_manifests. Verified:
  296 projects total, incl. `src/third_party/kernel/v6.6` @ `8df27f5…` (R138 chromeos-6.6),
  matching the USB's 6.6.99-fyde kernel (Dec 2025). Fallback: r144-dev / R144-16503.B.
- **Board: `amd64-openfyde_slim`** — CONFIRMED (overlay repo `overlay-amd64-openfyde_slim`
  exists; matches USB label `amd64-fydeos_slim`).
- Kernel package: `chromeos-kernel-6_6`. Config fragment appended to
  `src/third_party/kernel/v6.6/chromeos/config/x86_64/common.config`.
- Tree location: `$HOME/openfyde/src`. Sync logs: `$HOME/openfyde/logs/`.

### ⚠️ Module-version caveat (handle at inject/boot stage)

The rootfs on the USB carries modules for `6.6.99-fyde`. Our rebuilt openFyde
kernel may report a slightly different `UTS_RELEASE` (e.g. `6.6.x-openfyde` or no
`-fyde`), so `/lib/modules/<ver>/` won't match → modules won't load. For the FIRST
boot test that's OK (goal is just to get *past the EFI freeze*; essential drivers
are built-in). To fully match, either set `CONFIG_LOCALVERSION` to reproduce
`-fyde` and match the sublevel, or rebuild/replace the rootfs modules. Note the
booted kernel version once it comes up and reconcile then.

---

## ⭐ RESUME HERE — status as of 2026-07-02 (end of session 1)

**FydeOS BOOTS on the Acer Iconia W4-820 from USB — reached the OOBE/language screen
with a working touchscreen.** The core project goal (custom kernel boots a 32-bit-UEFI
Bay Trail tablet) is DONE. NOTE: the full `repo sync` / `cros_sdk` approach above was
ABANDONED — we build the kernel STANDALONE (see below). Ignore the stale "Build target"
and repo-sync notes above; the standalone recipe is the source of truth.

### The winning setup (all durable in the repo + release `booting-2026-07-02`)
- **Kernel**: openFyde R138 kernel git (`~/openfyde/kernel-6.6`, tag 6.6.76), built
  STANDALONE with plain `make` (no cros_sdk). Exact config saved at
  `boards/iconia-w4-820/kernel-6.6.76-working.config`. Config = generic x86_64 flavour
  + these fragments (in `boards/iconia-w4-820/config/` + shared `config/efi-mixed.config`):
  `efi-mixed` (EFI_MIXED+HANDOVER+STUB), `trim` (drop nouveau/media), `debug-console`
  (SERIAL_8250_CONSOLE→EFI_EARLYCON, FB_EFI, SYSFB_SIMPLEFB), `tpm` (TCG_VTPM_PROXY),
  `debug-capture` (VFAT/NLS builtin). xloadflags = **0x3f**. Artifact:
  `boards/iconia-w4-820/out/vmlinuz`, sha `2c42d429…`.
- **Bootloader**: self-built i386-efi GRUB core via `scripts/build-grub-ia32.sh`
  (`bootia32.efi`, prefix `/boot/grub`, ~512K). Reads `/boot/grub/grub.cfg` on the ESP.
- **Modules**: rebuilt to MATCH the kernel config (`modules-6.6.76-v5.tar`, sha
  `059c710f…`) and injected into ROOT-A. CRITICAL: modules.builtin must list
  tpm_vtpm_proxy or `modprobe tpm_vtpm_proxy` in tpm2-simulator pre-start fails.
- **Rootfs write access**: clear the ext ro-compat tamper byte —
  `dd if=/dev/zero of=<ROOT-A> bs=1 seek=1127 count=1 conv=notrunc` — then mount `-t ext4` rw.
- **grub.cfg** (production, i915 flicker fixes): `boards/iconia-w4-820/boot/grub.cfg`.

### Debugging harness that worked
- Can't interact with tablet (OTG keyboard dead). Capture boot via an init wrapper
  (`init=/sbin/iconia-dbg`) that dumps `dmesg` — the rootfs-write variant reached 36s;
  root cause found by reading `/etc/init/tpm2-simulator.conf` statically.
- USB↔laptop transfer: Crostini home is visible to the crosh host at
  `/media/fuse/crostini_1910d1979a76c12e132e98ff6ca5833087b4d2ce_termina_penguin/`
  (writable both ways — used it to pull `kern-a.bin` from the host too).
- All work: `inspect`/`inject` in crosh `shell`; kernel/module BUILD in Crostini.

### Flicker fix — CONFIRMED (session 2, 2026-07-02)
- Production grub.cfg with **i915.enable_psr=0 enable_fbc=0 enable_dc=0** written to
  USB ESP (`/dev/sda12`, part 12) and verified by SHA
  (`9f62151bc57c39afd366a8bdf6f203ddae3d930376502b9d0851196bf75aae09`, matches repo
  `boards/iconia-w4-820/boot/grub.cfg`). Booted on tablet → **no flicker, much smoother.**
  Bay Trail PSR was the cause. This grub.cfg is the production baseline going forward.
- Slowness is partly inherent (2GB + running off slow USB) — eMMC install will help.

## ⭐ SESSION 2 — status as of 2026-07-02

**Flicker FIXED and eMMC INSTALL DONE.** FydeOS is installed to the tablet's
eMMC and the firmware boots OUR GRUB from it. Remaining wart: the kernel's eMMC
enumeration is intermittent, so eMMC boot succeeds only ~1-in-3 tries.

### What worked
- **i915 flicker fix CONFIRMED**: production grub.cfg (`enable_psr=0 enable_fbc=0
  enable_dc=0`) → no flicker, smooth. This is the boot baseline.
- **eMMC install via PID-1 (init=) — the winning method.** The upstart-triggered
  approaches all FAILED: the tablet's service layer crash-loops (shill/btmanagerd
  SIGABRT on missing modules) + intermittent `i2c_designware` "timeout waiting for
  bus ready", so upstart milestones never settle and the job never fired. Switched
  to `init=/sbin/iconia-init.sh` (runs as PID 1, before upstart). It: mounts
  essentials, does a **udev coldplug** (sdhci-acpi is built-in but its probe defers
  until udev processes uevents — without this /dev/mmcblk0 never appears), runs
  `chromeos-install --dst /dev/mmcblk0 --yes`, re-injects our 0x3f vmlinuz +
  bootia32.efi + grub.cfg (PARTUUID fixed to eMMC ROOT-A) onto the eMMC ESP, and
  powers off. Scripts: `boards/iconia-w4-820/install/{iconia-init,iconia-fixboot,
  iconia-emmc-debug}.sh` + `iconia-install.conf` (obsolete upstart attempt).
- **eMMC install SUCCEEDED**: eMMC ROOT-A PARTUUID=`95DE10DD-E5AA-0C49-8E23-A32012F41F14`,
  eMMC vmlinuz xloadflags=`3f`. (postinst "verity hash verification failed" is
  EXPECTED/harmless — we modified the rootfs and DON'T use ChromeOS verified boot;
  we boot GRUB → vmlinuz → root=PARTUUID ro directly.)
- **"No bootable device" FIXED via the bootmgfw trick.** A fixed eMMC boots only
  via the firmware's persistent NVRAM "Windows Boot Manager" entry
  (→ `\EFI\Microsoft\Boot\bootmgfw.efi`), NOT the removable-media fallback
  (`\EFI\BOOT\BOOTIA32.EFI`) that boots the USB. No efivarfs (CONFIG_EFIVAR_FS
  unset) to add an entry, so we copy our GRUB to that bootmgfw path
  (`iconia-fixboot.sh`, now also folded into `iconia-init.sh`). Firmware then
  loads our GRUB from eMMC → "Booting FydeOS".

### The remaining problem — intermittent eMMC enumeration (KERNEL, not HW)
- Firmware reads the eMMC reliably (loads bootmgfw→GRUB→vmlinuz off it fine, and
  Windows booted it). The flakiness is purely the **Linux eMMC driver**: mmcblk0
  enumerates only ~1/3 of boots; HS200 tuning likely intermittently fails. On eMMC
  boot the kernel then hangs at `rootwait` waiting for mmcblk0p3.
- Root cause = generic+trimmed kernel missing Bay Trail support. Config gaps found:
  `CONFIG_I2C_DESIGNWARE_BAYTRAIL` unset; AXP288 PMIC + REGULATOR_AXP + PMIC_OPREGION
  all absent.
- **STAGED next experiment (ready to deploy): `iconia-emmc-debug.sh`** — re-injects
  the eMMC grub.cfg with `sdhci.debug_quirks2=0x40` (SDHCI_QUIRK2_BROKEN_HS200 →
  disable HS200, force a robuster mode) + a debug console (console=tty1 loglevel=7).
  One boot then either boots reliably (quirk worked) or shows where it hangs.
- **Proper fix if the quirk isn't enough: kernel rebuild** enabling
  CONFIG_I2C_DESIGNWARE_BAYTRAIL + AXP288 PMIC/regulator/OPREGION (relax the trim),
  rebuild kernel+modules, re-inject to eMMC ESP + ROOT-A.

### Deploy recipe (build host crosh; USB moves letters sda<->sdb)
```sh
# find USB (7.45GiB = 15633408 sectors), mount, copy a script, point grub init= at it
U=""; for d in sda sdb sdc; do [ "$(cat /sys/block/$d/size 2>/dev/null)" = 15633408 ] && U=$d; done
sudo mount /dev/${U}3 /tmp/roota; sudo mount -o remount,rw /tmp/roota; sudo mount /dev/${U}12 /tmp/esp
SRC=/media/fuse/crostini_1910d1979a76c12e132e98ff6ca5833087b4d2ce_termina_penguin/source/neilgfoster/iconia/boards/iconia-w4-820/install
sudo cp "$SRC/<script>.sh" /tmp/roota/sbin/<script>.sh; sudo chmod +x /tmp/roota/sbin/<script>.sh
sudo sed -i 's#init=[^ ]*#init=/sbin/<script>.sh#' /tmp/esp/boot/grub/grub.cfg   # or init=/sbin/init for normal
sync; sudo umount /tmp/esp; sudo umount /tmp/roota
# read a PID1 script's trace afterward: mount /dev/${U}3 and cat /iconia-*.log
```
- USB rootfs ro-compat already cleared → `mount -o remount,rw` works. Crostini home
  visible to crosh host at the /media/fuse/... path above (repo lives there).
- PID1 scripts log live to /dev/tty1 (+ /dev/kmsg) AND to a trace file on ROOT-A
  (`/iconia-*.log`) — the ONLY reliable channel (USB-ESP FAT logs / dmesg / stateful
  are lost on the hard power-offs these debug boots need).

## ✅ MILESTONE 8 COMPLETE — eMMC boots standalone to OOBE (2026-07-03)

Full keyboard-free eMMC install achieved. Recap of what made it work:
- **Install**: `iconia-init.sh` as PID 1 (init=) — coldplug udev, chromeos-install,
  re-inject 0x3f kernel + bootia32.efi + grub.cfg (eMMC PARTUUID) + bootmgfw.efi.
- **Bootable**: bootmgfw trick (GRUB at `\EFI\Microsoft\Boot\bootmgfw.efi`).
- **Reliable eMMC**: `sdhci.debug_quirks2=0x40` (HS200 off) in grub, AND for USB
  utility boots, `iconia-emmc-finalize.sh` force-rebinds sdhci-acpi to make the
  eMMC enumerate. KEY GOTCHA: rebinding RENUMBERS mmc hosts (eMMC may become
  mmcblk1), so detect the eMMC by identity (big ~58GiB mmcblk), not fixed mmcblk0.
- **OOBE**: had to re-enable `ui.conf` on eMMC ROOT-A (we'd disabled it on the USB
  rootfs for PID1 console debugging; chromeos-install copied that to eMMC).
- **Prod grub keeps the boot console** (console=tty1 loglevel=7, no keep_bootcon) —
  user wants visible boot activity, not a blank/frozen screen.

eMMC ROOT-A PARTUUID = `95DE10DD-E5AA-0C49-8E23-A32012F41F14`.

## Next actions (session 3)
1. ✅ **eMMC boot reliability CONFIRMED** — ~5/5 cold power-cycles booted to OOBE
   with the HS200-off quirk. (If a boot ever hangs at rootwait, the durable fix is
   the Bay Trail kernel rebuild below.)
2. ✅ **Wi-Fi WORKS** (BCM43241) — depmod + fw decompress + NVRAM (iconia-wifi-fix.sh).
   Remaining HW follow-ups now that module autoload works: audio (fw_sst decompressed
   this pass — re-test), bluetooth, backlight, sensors/auto-rotate. See hardware-status.md.
   Wi-Fi (brcmfmac + firmware/NVRAM), audio (fw_sst_0f28.bin + UCM), backlight,
   auto-rotate/sensors, bluetooth. WiFi is needed to complete OOBE sign-in.
3. **Optional kernel rebuild** enabling `CONFIG_I2C_DESIGNWARE_BAYTRAIL` + AXP288
   PMIC/regulator/OPREGION (relax trim) — would make eMMC/I2C rock-solid and fix
   several HW subsystems at once. Then re-inject kernel+modules to eMMC.
4. **Disable auto-update** on the installed system (would overwrite our eMMC kernel
   with stock 0x2b).


1. Confirm the i915 flicker fix (grub `boots-2026-07-02` release `grub.cfg` /
   `boards/iconia-w4-820/boot/grub.cfg`). If flicker persists, try
   `i915.enable_dpcd_backlight=1` or panel-specific knobs.
2. **Milestone 8 — install to eMMC** (`/dev/mmcblk0` on the tablet, ~58GB):
   - Boot FydeOS from USB, run the FydeOS installer to the eMMC.
   - **BEFORE first eMMC boot** (installer writes the STOCK 0x2b kernel): re-apply our
     fixes to the eMMC — inject `vmlinuz` (0x3f) + `bootia32.efi` + grub.cfg on the eMMC
     ESP (partition 12), clear ro-compat + inject matching modules on eMMC ROOT-A
     (partition 3), and fix `root=PARTUUID=` (changes on eMMC — read with `cgpt`/`blkid`).
   - Same procedure as USB; just target `mmcblk0` instead of the USB disk.
3. Hardware follow-ups (see `boards/iconia-w4-820/hardware-status.md`): audio needs
   firmware (`fw_sst_0f28.bin` failed to load; SST `bytcr_rt5640` + UCM) — use
   `scripts/inject-rootfs.sh`. Check Wi-Fi/BT, backlight, battery.
4. Auto-update will overwrite the eMMC kernel with stock 0x2b → disable auto-update
   on the installed system, or be ready to re-inject.

## Handy commands

```sh
# decisive byte on any kernel image (want low byte with 0x04 set, e.g. 2f/3f):
od -An -tx1 -j $((0x236)) -N 2 vmlinuz.A
# make a ChromeOS rootfs (ext2 with 0xff ro-compat) writable:
dd if=/dev/zero of=<ROOTPART> bs=1 seek=1127 count=1 conv=notrunc   # then mount -t ext4 rw
# rebuild kernel standalone after a config change:
cd ~/openfyde/kernel-6.6 && make olddefconfig && make -j$(nproc) bzImage
# ALWAYS after a kernel config change, rebuild+re-inject modules (modules.builtin!):
make -j$(nproc) modules && make modules_install INSTALL_MOD_PATH=<stage>
```


## ⭐ SESSION 3 WRAP (2026-07-03)

Kernel rebuilt with Bay Trail HW enablement (`baytrail-hw.config`) → 6.6.76 #6,
xloadflags still 0x3f, re-injected to eMMC (`iconia-kernel-reinject.sh`).

**Working now:** eMMC standalone boot (first-try since the rebuild — i2c semaphore
likely fixed enumeration; HS200 quirk still in grub, try dropping it), **Wi-Fi**
(now native `.xz` firmware via `FW_LOADER_COMPRESS_XZ`), touchscreen, display.

**Still broken / follow-ups (all polish; device is usable):**
- **Backlight** ❌ HARD — `/sys/class/backlight` empty even with PWM_CRC; i915
  `[DSI-1] Failed to get the PMIC PWM chip`; Crystal Cove PMIC does NOT bind →
  board uses a different backlight PWM path. Needs investigation (AXP288 / LPSS
  PWM / panel-native). Screen usable at full brightness.
- **Audio** ❌ — SST vs SOF contend, no firmware/topology/UCM.
- **Auto-rotate/sensors** ❌ — accel didn't come up (SMO91D0 hub / i2c).
- **Bluetooth** 🟡 — stack loads, no hci0 (UART controller not bound).

**Utility-boot pattern (all the `iconia-*.sh` in `install/`):** deploy script to
USB `/sbin`, point grub `init=` at it, PID1 does the work, logs to ROOT-A trace +
/dev/tty1, powers off. eMMC reached via sdhci-acpi rebind + identity detect
(rebind RENUMBERS mmc → find big mmcblk). **USB ROOT-A is ~100% full & re-enumerates
sda<->sdb** — mount fresh each time; free space by removing decompressed fw dupes.

## ✅ BACKLIGHT FIXED (session 4, 2026-07-03)

**Brightness slider works.** Root cause was a two-part kernel gap, found via
`iconia-backlight-diag.sh` (raw-PWM dim test confirmed the HW path):
1. `# CONFIG_GPIO_CRYSTAL_COVE is not set` — the `gpio_crystalcove` GPIO chip
   i915's DSI/VBT panel code needs to "own" the panel never registered. Fixed:
   `CONFIG_GPIO_CRYSTAL_COVE=y` (in `baytrail-hw.config`). PWM_CRC/INTEL_SOC_PMIC
   were already on — that's why raw `pwmchip0` (crystal_cove_pwm) dimmed the panel.
2. **Probe-ordering race**: even with the GPIO chip enabled, built-in i915 probes
   (~17.7s) BEFORE the Crystal Cove MFD/GPIO (on the async i2c-designware bus)
   registers `gpio_crystalcove` (~18.1s) → i915 logs "cannot find GPIO chip
   gpio_crystalcove, deferring" → "Failed to own gpio for panel control" → "Failed
   to get the PMIC PWM chip" and never retries. Fix: **`CONFIG_DRM_I915=m`** — i915
   loads from userspace AFTER the PMIC/GPIO are up. (This is also how ChromeOS ships
   i915 natively; building it in was our deviation.) Kernel = **6.6.76 #8**,
   xloadflags still 0x3f.

**Space gotcha (important for any future reinject):** i915-as-a-module grew the
module tar 153M→**201M**, which OVERRAN eMMC ROOT-A (only ~159M free). `iconia-
kernel-reinject.sh` now reclaims space before extract: (a) drop decompressed
firmware that has an `.xz` sibling, (b) `rm -rf` firmware for hardware this tablet
lacks (amdgpu/radeon/nvidia/iwlwifi/ath*/rtw*/mediatek/qcom/… — KEEP i915, brcm,
intel audio, regulatory.db). A FAILED reinject leaves a partial module tree (rm ran
+ extract died) → device bootloops (last console line "bootconsole disabled"); the
cure is simply a successful reinject.

## 🟡 AUTO-ROTATE: kernel DONE, blocked on FydeOS userspace (session 4, 2026-07-03)

The accelerometer is an **STMicro HID-over-I2C sensor hub** (ACPI `SMO91D0`, _CID
`PNP0C50`, VID:PID `0483:91D1`), NOT a raw IIO accel — its report descriptor is a
standard HID sensor (usage page `05 20`, accel collection `09 73`). Enabled the HID
sensor stack (`HID_SENSOR_HUB` + `HID_SENSOR_ACCEL_3D`/gyro/magn/incl/rotation/als,
all `=m`) in `baytrail-hw.config` → kernel **6.6.76 #9**. **Verified on the eMMC**
(via `iconia-emmc-sensor-check.sh` — LoadPin blocks side-loading modules from a
non-booted rootfs, so the test must run on the eMMC): `hid-sensor-hub` binds
SMO91D0 and all six iio devices appear incl. `iio:device3 name=accel_3d` and
`dev_rotation`. **So the kernel side is complete; remaining no-rotate is FydeOS
userspace** (iioservice/mems_setup: the HID accel likely lacks a `location=lid`
tag / mount-matrix wiring Chrome needs). Kernel diag artifacts:
`install/iconia-sensor-diag.sh`, `iconia-sensor-load.sh` (LoadPin-blocked),
`iconia-emmc-sensor-check.sh`.

**Force-load experiment RULED OUT module-timing (2026-07-03):** `iconia-sensor-
boot.sh` (PID1 pre-init that modprobes the whole HID-sensor stack, then
`exec /sbin/init`) armed via `iconia-emmc-armsensor.sh`. Booted to OOBE with
accel_3d loaded before init → **still no rotation**. So it is NOT a load/timing
issue; it is FydeOS iioservice/Chrome not adopting the HID accel as the lid
rotation sensor. Next attempt (needs dev-mode/crosh shell): inspect
`/run/iioservice`, `mems_setup`, udev `*iioservice*` rules; likely need to tag the
accel with `location`/`label=accel-display` + an identity mount-matrix so
iioservice exposes it to Chrome. The `armsensor` toggle can DISARM (restore
init=/sbin/init) by re-running it.

## ✅ AUDIO FIXED (session 4, 2026-07-03) — speaker works, survives reboot

Codec = **Realtek RT5640** (i2c `10EC5640`); DSP = **legacy SST atom** (card 0
`bytcr-rt5640`, config `stereo-spk-dmic1-mic`; SOF also present but SST won). Two
parts:
1. **Kernel**: trim.config had dropped `SND_SOC_RT5640` + `SND_SOC_INTEL_BYTCR_RT5640_MACH`
   → no card. Enabled both → kernel **6.6.76 #10** (in `baytrail-hw.config`).
2. **UCM (the real blocker)**: FydeOS ships UCM only for `sof-hda-dsp`, nothing for
   our card, so CRAS couldn't route it (raw `aplay hw:0,0` failed hw_params = DPCM
   FE had no connected BE). Fix: a **self-contained `bytcr-rt5640` UCM** built from
   alsa-ucm-conf's verified sequences (bytcr PlatformEnableSeq DSP pipe +
   rt5640 EnableSeq codec routing in SectionVerb; Speaker enable in the device;
   volume mapped to `Speaker Playback Volume`/`DAC1`). Proven live: manual amixer
   sequence → white noise → YouTube; then installed UCM → **sound survives cold
   reboot**. On-screen volume works.

Repo artifacts: `boards/iconia-w4-820/audio/{HiFi.conf,bytcr-rt5640.conf}` +
`install/iconia-ucm-install.sh` (remounts rootfs rw, drops UCM into
`/usr/share/alsa/ucm2/conf.d/bytcr-rt5640/`, symlinks `bytcrrt5640`, restarts cras).
NOTE: UCM was installed to the live eMMC rootfs at runtime — bake it into the rootfs
image for a clean reproducible build. Diag: `install/iconia-audio-diag.sh`.

### 🔑 SSH LIVE-DEBUG WORKS (session 4) — huge workflow unlock
Root shell on tablet over wifi ended the multi-boot loop. What finally worked:
FydeOS `sshd_config` wants host keys at `/mnt/stateful_partition/etc/ssh/` (copied
ours there); then run sshd manually (NOT persistent yet). Connect from the **crosh
host** (Crostini can't reach LAN): `ssh -i /tmp/ik root@192.168.1.31` (key =
build-host `~/.ssh/iconia_ed25519`, copied to crosh `/tmp/ik`). Push local scripts:
`ssh ... 'sh -s' < /media/fuse/<crostini>/<file>`. `stop powerd` first (suspend/
resume broken — screen won't wake). TODO: make sshd auto-start at boot (privsep
preauth-255 with our own invocation is unsolved; manual start works).

## 🔧 SSH-for-live-debug (in progress, session 4) — the current focus

Goal: a root shell on the tablet to iterate audio/sensors without the multi-boot
PID1 loop (OTG keyboard now works; dev mode + `cros_debug` enabled; crosh `shell`
works; tablet IP **192.168.1.31**). Facts established:
- Our debug SSH key: build host `~/.ssh/iconia_ed25519` (pub in tablet
  `/root/.ssh/authorized_keys`). Crostini CANNOT reach the LAN (NAT) — ssh must run
  from the crosh host (on LAN) or a local agent.
- FydeOS `sshd_config` expects host keys at **`/mnt/stateful_partition/etc/ssh/`**
  (not /etc/ssh). Copied ours there.
- Inbound is firewalled: `iptables -I INPUT -p tcp --dport 22 -j ACCEPT` (resets each
  boot). Suspend/resume is broken (screen won't wake) → run `stop powerd` while
  debugging.
- **BLOCKER**: manual `sshd -o UsePAM=no -o PermitRootLogin=prohibit-password -o
  AuthorizedKeysFile=/root/.ssh/authorized_keys` LISTENS and accepts the connection,
  but the **preauth privsep child exits 255 right after `permanently_set_uid`** (no
  `fatal:` line; no seccomp dmesg because `audit=0`). Kernel HAS SECCOMP+FILTER.
- `fydeos-sshd-server` job = reverse tunnel for cloud "remote-help", NOT a local
  listener (dead end). **UNTRIED: `start openssh-server`** (the other job in
  /etc/init) — may be a normal local sshd that just works; try this FIRST.
- Also install an x86_64 static node for a LOCAL agent: ChromeOS base has **no
  libstdc++**, so official node fails; use a self-contained build or ship libstdc++.
  `/usr/local` is writable+exec in dev mode.
- Repo: `install/iconia-emmc-sshsetup.sh` installs sshd via upstart + adds
  `cros_debug` to eMMC grub. Prod grub.cfg now carries `cros_debug` [[iconia-final-build-cros-debug]].

## 🟠 AUTO-ROTATE (session 4, 2026-07-03) — kernel/sensor DONE, blocked in iioservice

Chased end-to-end over the live SSH shell. What WORKS now:
- Tablet mode forced via `/etc/chrome_dev.conf` (`--enable-tablet-form-factor`
  `--force-tablet-mode=touch_view`). ChromeOS UI is in tablet mode.
- HID accel driver patched (`patches/hid-accel-rotation.patch`, applied to
  `~/openfyde/kernel-6.6/drivers/iio/accel/hid-sensor-accel-3d.c`): exposes
  `label=accel-display`, `in_accel_location=lid` (ext_info SHARED_BY_TYPE), and
  `in_accel_mount_matrix` (identity). iioservice now reads all of these (its
  location/label/mount_matrix errors are gone for accel_3d).
- **Chrome ADOPTS the accel**: chrome log shows `Enter tablet mode` + ash
  `accel_gyro_samples_observer` actively polling the accel device.
- **Sensor streams**: reading `/dev/iio:deviceN` directly (buffer enabled, freq=10,
  record=24B: 3×s32 + s64 ts) yields live changing X/Y/Z at ~10Hz.

THE WALL: ash logs `Device N: A read timed out` repeatedly — **iioservice's
buffered read of the accel times out even though the raw buffer streams when we
read it directly**. freq is correctly 10, buffer/buffer0 enabled. The one thing
iioservice still can't read is `in_accel_sampling_frequency_available` (ENOENT).
Likely a closed iioservice ↔ iio buffer-fd interaction; skeptical the missing
`_available` is the cause since the rate is already set and the buffer streams.
=> Kernel/sensor side is COMPLETE; remaining work is in closed ChromeOS userspace
(iioservice/ash) or a subtle iio buffer-fd path. Reasonable to PARK here.

**Vermagic gotcha for module-only rebuilds** (learned here): editing a kernel
source file makes the tree dirty → module vermagic gets `-dirty` and won't load on
the deployed #10 kernel (`6.6.76-gabcfb16364e1`). Fix: patched
`scripts/setlocalversion` to call `scm_version --no-dirty` (in the patch). Then a
single `.ko` can be rebuilt + hot-pushed over SSH:
`ssh root@IP 'mount -o remount,rw /; cat > /lib/modules/<ver>/kernel/.../x.ko.gz; mount -o remount,ro /' < x.ko.gz` then reboot.

## ✅ DEFAULT PORTRAIT + TABLET MODE (session 4, 2026-07-04)

Device boots to **tablet mode, portrait, right-side-up**, persistent, with manual
rotation (Ctrl+Shift+Refresh). Auto-rotate still parked. Full how-to +
reproducible artifacts: `boards/iconia-w4-820/display/`. Summary:
- Kernel **DRM panel-orientation quirk** (`lcd800x1280_leftside_up`) for
  `Iconia W4-820P` → desktop defaults to right-side-up portrait persistently
  (ChromeOS wouldn't persist a manual rotation; no stable EDID). In
  `patches/hid-accel-rotation.patch`; bzImage rebuild, vermagic unchanged.
- **cros_config form-factor=CHROMESLATE** (`display/configfs-chromeslate.img`).
- `/etc/chrome_dev.conf`: `--force-tablet-mode=touch_view` (tablet mode).
- **Boot splash** pre-rotated +90° (`display/boot-splash-portrait.tar`) — frecon
  has no rotate flag and interprets orientation opposite to Chrome.

## ⭐ SESSION 4 WRAP (2026-07-04) — big session

Delivered (all live-debugged over the new SSH channel — the key unlock):
- ✅ **Backlight** — `GPIO_CRYSTAL_COVE=y` + `DRM_I915=m` (probe-order race).
- ✅ **Audio** — RT5640 + bytcr_rt5640 machine driver + self-contained
  `bytcr-rt5640` UCM (`audio/`); survives reboot; on-screen volume works.
- ✅ **SSH live-debug** — root shell over wifi; ended the multi-boot loop.
  Persistent across reboot. Connect from crosh host: `ssh -i /tmp/ik root@<ip>`.
- ✅ **Default portrait + tablet mode** (this section).
- 🟠 **Auto-rotate** — sensor/kernel/metadata all perfect; Chrome reads samples
  (timeouts=0); blocked in closed ash rotation state machine. Parked.

Kernel is now **6.6.76-gabcfb16364e1** (stable vermagic via `--no-dirty`), built
from `~/openfyde/kernel-6.6` with `baytrail-hw.config` + the patch. Single-module
hot-rebuild+SSH-push workflow proven (see PROGRESS above / display/README.md).

## Next actions (session 5)

**State: device is a genuinely usable FydeOS tablet — boots eMMC standalone;
wifi, touch, display, brightness, AUDIO, tablet-mode + portrait all work.**

1. **Bake everything into a reproducible image build** (currently many fixes are
   hot-applied to the live eMMC over SSH). Fold into the rootfs/kernel build:
   the kernel patch, `baytrail-hw.config`, the UCM, cros_config CHROMESLATE,
   chrome_dev.conf flag, rotated splash, sshd autostart.
2. **Disable auto-update** (would overwrite our 0x3f/patched kernel with stock 0x2b).
3. Remaining HW polish (optional): **bluetooth** (no hci0; hci_uart/serdev bind +
   BCM .hcd), **hardware volume/buttons**, **drop HS200 quirk** (`sdhci.debug_quirks2=0x40`).
4. **Auto-rotate** revisit only with iioservice debug logging or a Chrome/ash
   angle — it's the closed layer; low ROI.

--- (older session-4 target list retained below) ---

**State: BACKLIGHT DONE; AUDIO DONE (UCM);
AUTO-ROTATE kernel-ready (accel_3d enumerates) but not rotating (FydeOS userspace).
Tablet boots FydeOS from eMMC standalone; wifi/touch/display/brightness work.
Kernel now 6.6.76 #10 (i915=m + HID sensors + RT5640). Actively standing up SSH/
local-agent for live debugging.**

Build artifacts on the Crostini build host (NOT in git): `~/openfyde/kernel-6.6/`
(.config = #8, i915=m), `~/openfyde/modules-baytrail.tar` (201M, i915=m set),
`boards/iconia-w4-820/out/vmlinuz` (#8). Reinject via `iconia-kernel-reinject.sh`
(tar→USB p1, vmlinuz→USB ESP p12; depmod runs on-device).

Build artifacts on the Crostini build host (NOT in git):
- `~/openfyde/kernel-6.6/` — tree; `.config` = Bay Trail build #6. Rebuild:
  `cd ~/openfyde/kernel-6.6 && make -j8 bzImage modules` (keep xloadflags 0x3f).
  bzImage == `boards/iconia-w4-820/out/vmlinuz` (sha 6b72156f).
- `~/openfyde/modules-baytrail.tar` (153M) — injected module set.
- Re-inject a new build via `iconia-kernel-reinject.sh` (stage tar→USB p1,
  vmlinuz→USB ESP). depmod runs ON-DEVICE (build-host depmod can't read .ko.gz).

Pick a target:
1. ✅ **Backlight — DONE** (see section above: GPIO_CRYSTAL_COVE=y + DRM_I915=m).
2. **Audio** — rootfs uses `snd_sof`; likely need `intel/sof/sof-byt*.ri` +
   `intel/sof-tplg/*.tplg` + ALSA UCM; blacklist legacy `intel_sst` so they don't
   contend (or vice versa). Firmware loads from .xz natively now.
3. **Drop HS200 quirk?** eMMC booted first-try on Bay Trail kernel — try removing
   `sdhci.debug_quirks2=0x40` from eMMC grub over several cold boots.
4. **Bluetooth** — no hci0; needs `hci_uart`/serdev bind + `BCM-0bb4-0306.hcd`.
5. **Sensors/auto-rotate** — accel (`SMO91D0`/`kxcjk`) didn't enumerate.

Utility-boot how-to: deploy `install/iconia-*.sh` to USB `/sbin`, `sed` grub
`init=` to it, boot USB, read ROOT-A trace. USB ROOT-A ~full & re-enumerates
sda<->sdb — mount FRESH each command; free space by deleting decompressed
`/lib/firmware/**` dupes (kernel loads .xz natively now). eMMC PARTUUID
95DE10DD-E5AA-0C49-8E23-A32012F41F14.
