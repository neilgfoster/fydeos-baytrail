# iconia

Boot and install **FydeOS / openFyde** on an **Acer Iconia W4-820** (and similar
Bay Trail tablets with **32-bit UEFI firmware**) by building a custom kernel with
`CONFIG_EFI_MIXED` and injecting it into a stock FydeOS installer USB.

## The problem in one paragraph

The Iconia W4-820 has a **64-bit CPU** (Intel Atom Z3740D, Bay Trail-T) but a
**32-bit-only UEFI firmware**. Stock FydeOS installer USBs ship a 64-bit GRUB
(`bootx64.efi`) only, and — more fundamentally — a 64-bit kernel built **without**
`CONFIG_EFI_MIXED`. A 32-bit firmware can neither launch the 64-bit GRUB nor hand
off to that kernel. Adding a 32-bit GRUB (`bootia32.efi`) is easy and works; the
real blocker is the kernel, which lacks the **32-bit EFI handover entry point**
(`XLF_EFI_HANDOVER_32`). This repo rebuilds the openFyde kernel with that entry
point enabled and swaps it onto the installer USB.

See [`docs/findings.md`](docs/findings.md) for the full diagnostic trail.

## Repeatable process

```
┌─────────────────┐   ┌──────────────────┐   ┌───────────────────┐
│ 1. inspect USB  │──▶│ 2. build kernel  │──▶│ 3. inject + boot  │
│ (on FydeOS host)│   │ (openFyde SDK)   │   │ (on FydeOS host)  │
└─────────────────┘   └──────────────────┘   └───────────────────┘
```

1. **`scripts/inspect-usb.sh`** — run on the FydeOS/ChromeOS host (crosh `shell`)
   with the installer USB plugged in. Auto-detects the installer, mounts its EFI
   System Partition read-only, and reports the **kernel version**, **`xloadflags`**
   (whether the 32-bit handover bit is set), **kernel command lines**, and
   **PARTUUIDs**. Writes a machine-readable `usb-profile.env`.

2. **`scripts/build-kernel.sh`** — run in a beefy x86_64 Linux env (a FydeOS
   Crostini container works: ~120 GB free disk + 16 GB RAM needed). Syncs
   openFyde, applies [`config/efi-mixed.config`](config/efi-mixed.config), builds
   just the `chromeos-kernel` package, and emits a new `vmlinuz` whose
   `XLF_EFI_HANDOVER_32` bit is **set**.

3. **`scripts/inject-kernel.sh`** — run on the FydeOS host. Backs up the original
   `vmlinuz.A`/`vmlinuz.B` on the USB's ESP, drops in the custom kernel, and
   (re)installs `bootia32.efi` + a `gptpriority`-free `grub.cfg` so 32-bit
   firmware can boot the whole chain.

## Quick check that a rebuild worked

The single byte that matters is `xloadflags` at offset `0x236` of the kernel
image. Bit `0x04` (`XLF_EFI_HANDOVER_32`) must be **set**:

```sh
# stock FydeOS kernel: prints "2b 00"  -> 0x04 CLEAR -> won't boot on 32-bit UEFI
# rebuilt kernel:      prints "2f 00"  -> 0x04 SET   -> boots
od -An -tx1 -j $((0x236)) -N 2 /path/to/vmlinuz.A
```

## Status

- [x] Diagnose: confirmed stock FydeOS kernel lacks `XLF_EFI_HANDOVER_32` (`0x2b`).
- [x] 32-bit GRUB (`bootia32.efi`) boots on the W4-820 (reaches kernel handoff).
- [x] `inspect-usb.sh`
- [ ] `build-kernel.sh` — openFyde package/config paths pinned once tree syncs.
- [ ] `inject-kernel.sh` verified end-to-end on hardware.
- [ ] Full install to eMMC (re-apply kernel to the eMMC ESP post-install).

## Caveats

- **Auto-updates clobber the kernel.** A FydeOS update ships a stock kernel and
  reverts the fix. The process here is deliberately repeatable so you can rebuild
  and re-inject. Consider disabling auto-update on the installed system.
- **eMMC install** clones the same (un-fixed) ESP to internal storage, and the
  PARTUUIDs change. After installing, re-run the inject step against the eMMC ESP.
