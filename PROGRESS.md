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
| 6 | Build kernel with EFI_MIXED; verify `xloadflags`=`0x2f` | ⬜ TODO |
| 7 | Inject to USB; boot tablet past the freeze | ⬜ TODO |
| 8 | Install to eMMC; re-inject kernel to eMMC ESP; standalone boot | ⬜ TODO |

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
- openFyde tree syncing (background) at `$HOME/openfyde/src`; not yet complete.

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

## Next actions (do these next session)

1. Continue/verify the openFyde **sync** — STARTED 2026-07-01 in background at
   `$HOME/openfyde/src` (log path in `$HOME/openfyde/logs/latest-sync-log.path`).
   If incomplete/interrupted, resume with `repo sync` (it's incremental) or
   `scripts/build-kernel.sh --board iconia-w4-820 sync`.
2. `scripts/build-kernel.sh --board iconia-w4-820 config` → review `build.env`; confirm board string and
   that `chromeos-kernel-6_6` ebuild exists.
3. Enter `cros_sdk` (from `$HOME/openfyde/src`), `setup_board --board=amd64-openfyde_slim`,
   build the kernel (`scripts/build-kernel.sh --board iconia-w4-820 build` prints the exact emerge cmds),
   then `scripts/build-kernel.sh --board iconia-w4-820 extract`.
4. Verify `out/vmlinuz` xloadflags low byte has bit `0x04` set (→ `0x2f`).
5. `inject-kernel.sh --board iconia-w4-820`; boot-test the tablet; note booted kernel
   version + whether modules loaded (see caveat above).
6. On success: install to eMMC, then re-inject kernel to the eMMC ESP.

## Handy commands

```sh
# read the decisive byte on any kernel image:
od -An -tx1 -j $((0x236)) -N 2 vmlinuz.A     # want low byte with 0x04 set (e.g. 2f)
```
