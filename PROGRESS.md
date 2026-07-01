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

Full reasoning: [`docs/findings.md`](docs/findings.md).

## Milestones

| # | Milestone | State |
|---|-----------|-------|
| 1 | Confirm USB is 64-bit-UEFI-only | ✅ done |
| 2 | Add `bootia32.efi` + clean grub.cfg; reach GRUB on tablet | ✅ done |
| 3 | Diagnose kernel freeze → missing `XLF_EFI_HANDOVER_32` (`0x2b`) | ✅ done |
| 4 | Scaffold repo + inspect/inject/build scripts | ✅ done |
| 5 | Sync openFyde, pin board + kernel package + config path | ⬜ TODO |
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
- Repo scaffolded; scripts written but **not yet run against real hardware/tree**.
- `bootia32.efi` + `grub.cfg` were manually placed on the USB earlier and confirmed
  to reach the kernel-handoff freeze. `inject-kernel.sh` reproduces that placement.
- No openFyde tree synced yet.

## Next actions (do these next session)

1. In crosh `shell`: run `scripts/inspect-usb.sh` against the USB; commit the
   resulting `usb-profile.env` here. This pins the **exact kernel version**.
2. Set `MANIFEST_BRANCH` in `build-kernel.sh` to match that kernel version.
3. In Crostini: `scripts/build-kernel.sh sync` (long), then `config`, review
   `build.env`, then `build` inside `cros_sdk`, then `extract`.
4. Verify `out/vmlinuz` reads `xloadflags` bit `0x04` set.
5. Inject and boot-test on the tablet.

## Handy commands

```sh
# read the decisive byte on any kernel image:
od -An -tx1 -j $((0x236)) -N 2 vmlinuz.A     # want low byte with 0x04 set (e.g. 2f)
```
