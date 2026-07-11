# iconia

Boot and install **FydeOS / openFyde** on **64-bit-CPU + 32-bit-UEFI** tablets
(Intel Bay Trail / Cherry Trail) by rebuilding the openFyde kernel with
`CONFIG_EFI_MIXED` and injecting it into a stock FydeOS installer USB.

Multi-board: shared boot machinery, one directory per device under
[`boards/`](boards/).

| Board | Status |
|-------|--------|
| **Acer Iconia W4-820** ([`boards/iconia-w4-820/`](boards/iconia-w4-820/)) | ✅ **Delivered + archived** — final build frozen ([delivery manifest](boards/iconia-w4-820/install/README.md)); unit physically retired (screen). |

Starting a new Bay Trail tablet? Read the distilled
[**Bay Trail playbook**](boards/_template/bay-trail-playbook.md) first, then
[`docs/adding-a-board.md`](docs/adding-a-board.md). Copy
[`boards/_template/`](boards/_template/) to `boards/<your-board-id>/`.

## The problem in one paragraph

These tablets have a **64-bit CPU** but a **32-bit-only UEFI firmware**. Stock
FydeOS installer USBs ship a 64-bit GRUB (`bootx64.efi`) only, and — more
fundamentally — a 64-bit kernel built **without** `CONFIG_EFI_MIXED`. A 32-bit
firmware can neither launch the 64-bit GRUB nor hand off to that kernel. Adding a
32-bit GRUB (`bootia32.efi`) is easy and works; the real blocker is the kernel,
which lacks the **32-bit EFI handover entry point** (`XLF_EFI_HANDOVER_32`). This
repo rebuilds the openFyde kernel with that entry point enabled and swaps it onto
the installer USB.

> **Not for genuinely 32-bit CPUs** (e.g. Clover Trail Z2760): a 64-bit FydeOS
> kernel cannot run on them at all. `EFI_MIXED` is about firmware bitness, not CPU
> bitness. See [`docs/adding-a-board.md`](docs/adding-a-board.md).

New device? → [`docs/adding-a-board.md`](docs/adding-a-board.md).
W4-820 diagnostic trail → [`boards/iconia-w4-820/findings.md`](boards/iconia-w4-820/findings.md).

## Repeatable process

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

### Hardware bring-up (after it boots)

The same rebuild pipeline addresses most Bay Trail hardware quirks (Wi-Fi, audio,
touch, backlight, sensors). Track them per device in
`boards/<id>/hardware-status.md`. Fixes land in one of four places (see
[`docs/hardware-status-legend.md`](docs/hardware-status-legend.md)): a **kernel**
config fragment (`boards/<id>/config/`) or patch (`boards/<id>/patches/`) →
rebuild; a **cmdline** tweak in the injected `grub.cfg` → no rebuild; or **rootfs**
blobs (firmware / ALSA UCM) staged in `boards/<id>/stage/` via
**`scripts/inject-rootfs.sh --board <id>`**. Firmware/ACPI/suspend bugs baked into
the 32-bit UEFI are not kernel-fixable.

## Quick check that a rebuild worked

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
docs/                       adding-a-board, hardware-status-legend
boards/<id>/                per-device: board.env, usb-profile.env, hardware-status.md,
                            findings.md, config/, patches/, stage/, out/
boards/_template/           copy to start a new board
PROGRESS.md                 cross-session source of truth
```

## Status (see PROGRESS.md for detail)

- [x] Diagnose: stock FydeOS kernel lacks `XLF_EFI_HANDOVER_32` (`0x2b`) — W4-820.
- [x] 32-bit GRUB (`bootia32.efi`) boots on the W4-820 (reaches kernel handoff).
- [x] Repo scaffolded + made multi-board; `inspect-usb.sh` run against real USB.
- [x] openFyde build target pinned (R138 / r138-dev / amd64-openfyde_slim); sync running.
- [ ] Build kernel with EFI_MIXED; verify `xloadflags`=`0x2f`.
- [ ] `inject-kernel.sh` verified end-to-end on hardware.
- [ ] Full install to eMMC (re-apply kernel to the eMMC ESP post-install).

## Caveats

- **Auto-updates clobber the kernel.** A FydeOS update ships a stock kernel and
  reverts the fix. The process here is deliberately repeatable so you can rebuild
  and re-inject. Consider disabling auto-update on the installed system.
- **eMMC install** clones the same (un-fixed) ESP to internal storage, and the
  PARTUUIDs change. After installing, re-run the inject step against the eMMC ESP.
