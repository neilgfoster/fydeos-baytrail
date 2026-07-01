# Boot-chain debugging — W4-820

Goal: get past the freeze at the GRUB→kernel handoff on 32-bit UEFI.

## Boot chain (self-built, controlled)

```
32-bit UEFI firmware
 └─ EFI/BOOT/BOOTIA32.EFI   = self-built grub-mkimage i386-efi core (~512K)
      prefix=/boot/grub → reads /boot/grub/grub.cfg on the ESP
 └─ grub.cfg: search kernel, `linux /syslinux/vmlinuz.A ...`, boot
 └─ vmlinuz.A = our 6.6.76 kernel, xloadflags 0x3f (EFI_MIXED handover set)
```

Build the GRUB core: `scripts/build-grub-ia32.sh` (needs `grub-efi-ia32-bin`).
Small on purpose — `grub-mkstandalone` output (~9M) does not fit the 32M ChromeOS ESP.

## What we've proven (with echo-instrumented grub.cfg)

| Stage | Result |
|-------|--------|
| Firmware launches our `bootia32.efi` | ✅ (grub banner prints) |
| GRUB `search` finds kernel partition | ✅ (`root=` prints) |
| GRUB `linux` loads the kernel | ✅ |
| GRUB `boot` → jumps to kernel | ✅ (`calling boot()...` prints) |
| **Kernel produces ANY output** | ❌ **nothing, even `earlyprintk=efi,keep`** |
| Outcome | frozen cursor, then reboot (≈? — 5min ⇒ UEFI watchdog) |

**Conclusion:** bootloader is fully working. The kernel dies in the earliest
mixed-mode entry, before it can print or disable the UEFI watchdog. Same symptom
for stock (0x2b) and our (0x3f) kernel.

## Constraint

The tablet's keyboard is on the same USB-OTG hub as the boot stick, so **no
interactive GRUB editing** (`e`) is possible. Every cmdline experiment must be
baked into `/boot/grub/grub.cfg` and re-injected via crosh (USB shuffled between
the tablet and the FydeOS laptop). Slow loop — prefer batching hypotheses.

## Hypotheses under test (cmdline, no rebuild)

1. `nokaslr` — KASLR under EFI mixed mode is a known early-crash source. [TESTING]
2. `no5lvl` — 5-level paging detection early path (config has X86_5LEVEL). [TESTING]

## If cmdline flags don't help — next options

- Rebuild kernel with `# CONFIG_RANDOMIZE_BASE`, `# CONFIG_X86_5LEVEL` off at
  compile time (more thorough than cmdline).
- Consider that this firmware's EFI may be hostile to mixed mode; cross-check
  against known-good Bay Trail Linux boots (Ubuntu bootia32 + amd64 kernel).
- Try a mainline/Debian `bootia32.efi` + a stock distro kernel as a control to
  confirm the hardware boots ANY 64-bit kernel via mixed mode.
