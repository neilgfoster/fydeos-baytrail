# fydeos-baytrail

Get **FydeOS / openFyde** running well on **Intel Bay Trail / Cherry Trail**
tablets — booting *and* the long tail of hardware bring-up (Wi-Fi, audio, sensors,
backlight, Bluetooth, power, ARC++). Works **regardless of UEFI bitness**:

- **64-bit UEFI** (e.g. Lenovo ThinkPad 10): stock FydeOS boots directly — you skip
  the boot fix and use this repo purely as the Bay Trail **hardware bring-up**
  framework (playbook, diagnostics, per-board fix tracking, rootfs/cmdline/kernel
  fixes).
- **32-bit UEFI** (e.g. Acer Iconia W4-820): the firmware also can't boot a stock
  64-bit installer, so this repo *additionally* rebuilds the openFyde kernel with
  `CONFIG_EFI_MIXED` and injects it onto the USB. See
  [the boot fix](#the-32-bit-uefi-boot-fix) below.

Multi-board: shared machinery, one directory per device under
[`boards/`](boards/).

| Board | Status |
|-------|--------|
| **Acer Iconia W4-820** ([`boards/iconia-w4-820/`](boards/iconia-w4-820/)) | ✅ **Delivered + archived** — final build frozen ([delivery manifest](boards/iconia-w4-820/install/README.md)); unit physically retired (screen). |

Starting a new Bay Trail tablet? Read the distilled
[**Bay Trail playbook**](docs/bay-trail-playbook.md) first, then
[`docs/adding-a-board.md`](docs/adding-a-board.md). Copy
[`boards/_template/`](boards/_template/) to `boards/<your-board-id>/`.

## First step for any new board: does it boot stock?

Write a **stock** FydeOS installer USB and try to boot it. That single test tells
you which path you're on:

- **It boots** → 64-bit UEFI. Install stock, then jump to
  [Hardware bring-up](#hardware-bring-up).
- **Firmware sees nothing bootable** → likely 32-bit UEFI. Apply
  [the boot fix](#the-32-bit-uefi-boot-fix) first.

> **CPU must be 64-bit either way.** A genuinely 32-bit CPU (e.g. Clover Trail
> Z2760) can't run FydeOS's 64-bit kernel at all — `EFI_MIXED` fixes *firmware*
> bitness, not CPU bitness.

New device? → [`docs/adding-a-board.md`](docs/adding-a-board.md).
W4-820 diagnostic trail → [`boards/iconia-w4-820/findings.md`](boards/iconia-w4-820/findings.md).

## The 32-bit-UEFI boot fix

*(Skip this whole section on 64-bit-UEFI boards — stock FydeOS already boots.)*

These tablets have a **64-bit CPU** but a **32-bit-only UEFI firmware**. Stock
FydeOS installer USBs ship a 64-bit GRUB (`bootx64.efi`) only, and — more
fundamentally — a 64-bit kernel built **without** `CONFIG_EFI_MIXED`. A 32-bit
firmware can neither launch the 64-bit GRUB nor hand off to that kernel. Adding a
32-bit GRUB (`bootia32.efi`) is easy and works; the real blocker is the kernel,
which lacks the **32-bit EFI handover entry point** (`XLF_EFI_HANDOVER_32`). This
repo rebuilds the openFyde kernel with that entry point enabled and swaps it onto
the installer USB.

### Boot-fix process (32-bit UEFI only)

```
┌─────────────────┐   ┌──────────────────┐   ┌───────────────────┐
│ 1. inspect USB  │──▶│ 2. build kernel  │──▶│ 3. inject + boot  │
│ (on FydeOS host)│   │ (openFyde SDK)   │   │ (on FydeOS host)  │
└─────────────────┘   └──────────────────┘   └───────────────────┘
```

All scripts take `--board <id>` (e.g. `--board iconia-w4-820`) and read/write that
board's directory under `boards/`.

1. **`scripts/inspect-usb.sh --board <id>`** — run on the FydeOS/ChromeOS host
   (crosh `shell`) with the installer USB plugged in. Auto-detects the installer,
   mounts its ESP read-only, and reports the **kernel version**, **`xloadflags`**
   (whether the 32-bit handover bit is set), **cmdlines**, and **PARTUUIDs**.
   Writes `boards/<id>/usb-profile.env`.

2. **`scripts/build-kernel.sh --board <id> {sync,config,build,extract}`** — run in
   a beefy x86_64 Linux env (a FydeOS Crostini container works: ~120 GB free disk
   + 16 GB RAM). Reads `boards/<id>/board.env` for the build target, syncs
   openFyde, applies [`config/efi-mixed.config`](config/efi-mixed.config) plus any
   board fragments/patches, builds just the kernel, and emits a `vmlinuz` whose
   `XLF_EFI_HANDOVER_32` bit is **set** → `boards/<id>/out/vmlinuz`.

3. **`scripts/inject-kernel.sh --board <id>`** — run on the FydeOS host. Backs up
   the original `vmlinuz` on the USB's ESP, drops in the custom kernel, and
   (re)installs `bootia32.efi` + a `gptpriority`-free `grub.cfg` so 32-bit
   firmware can boot the whole chain.

## Hardware bring-up

*Applies to every board, any UEFI bitness.*
This is the bulk of the work and it's identical whether the firmware is 32- or
64-bit — it's about the Bay Trail SoC and the FydeOS userland, not the bootloader.
**Read [`docs/bay-trail-playbook.md`](docs/bay-trail-playbook.md) first**, probe
with the shared [`diag/`](diag/) toolkit, and track results per device in
`boards/<id>/hardware-status.md`. Fixes land in one of four places (see
[`docs/hardware-status-legend.md`](docs/hardware-status-legend.md)):

- **kernel** config fragment (`boards/<id>/config/`) or patch
  (`boards/<id>/patches/`) → rebuild + re-inject `vmlinuz`. On 32-bit UEFI the
  rebuild also carries `efi-mixed.config`; on 64-bit UEFI it doesn't, and you swap
  the kernel on the existing `bootx64` chain (no `bootia32`/grub changes).
- **cmdline** tweak in `grub.cfg` → no rebuild.
- **rootfs** blobs (firmware / ALSA UCM) staged in `boards/<id>/stage/` via
  **`scripts/inject-rootfs.sh --board <id>`** → no rebuild.

Firmware/ACPI/suspend bugs baked into the UEFI itself are not kernel-fixable on
either bitness.

## Quick check that the boot fix worked (32-bit UEFI only)

The single byte that matters is `xloadflags` at offset `0x236` of the kernel
image. Bit `0x04` (`XLF_EFI_HANDOVER_32`) must be **set**:

```sh
# stock FydeOS kernel: prints "2b 00"  -> 0x04 CLEAR -> won't boot on 32-bit UEFI
# rebuilt kernel:      prints "2f 00"  -> 0x04 SET   -> boots
od -An -tx1 -j $((0x236)) -N 2 /path/to/vmlinuz.A
```

## Repo layout

```
config/efi-mixed.config     shared kernel enabler (all 32-bit-UEFI boards)
scripts/                    board-aware: inspect-usb, build-kernel, inject-kernel, inject-rootfs
diag/                       shared Bay Trail diagnostic toolkit (prior-art probes; not per-board)
docs/                       adding-a-board, bay-trail-playbook, hardware-status-legend
boards/<id>/                per-device: board.env, usb-profile.env, hardware-status.md,
                            findings.md, config/, patches/, stage/, out/
boards/_template/           copy to start a new board (skeleton only)
PROGRESS.md                 cross-session source of truth
```

Per-board status lives in the board table above and each board's
`hardware-status.md`; the full session-by-session trail is in
[`PROGRESS.md`](PROGRESS.md).

## Caveats

- **Auto-updates clobber the kernel.** A FydeOS update ships a stock kernel and
  reverts the fix. The process here is deliberately repeatable so you can rebuild
  and re-inject. Consider disabling auto-update on the installed system.
- **eMMC install** clones the same (un-fixed) ESP to internal storage, and the
  PARTUUIDs change. After installing, re-run the inject step against the eMMC ESP.
