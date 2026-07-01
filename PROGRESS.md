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
| 8 | Install to eMMC; re-inject kernel+modules to eMMC; standalone boot | ⬜ TODO (next) |

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

### In-flight when we stopped
- Just swapped grub to production cmdline with **i915.enable_psr=0 enable_fbc=0
  enable_dc=0** to fix the **flickering** (Bay Trail PSR). Awaiting confirmation it helped.
- Slowness is partly inherent (2GB + running off slow USB) — eMMC install will help.

## Next actions (session 2)

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
