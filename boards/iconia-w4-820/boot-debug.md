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

## CONTROL TEST RESULT (decisive)

Booted a known-good **Debian 6.1.0-47-amd64** kernel (xloadflags 0x7f) via our
self-built GRUB on the W4-820: **lots of kernel text + a kernel panic**. So:

- ✅ Hardware CAN boot a 64-bit kernel via EFI mixed mode
- ✅ Our self-built GRUB handover works
- ❌ The failure is SPECIFIC TO OUR openFyde kernel BUILD (not HW/bootloader)

## Root-cause hypothesis: our kernel booted SILENTLY

Our kernel config lacked EFI console options that Debian has:
- `CONFIG_EARLY_PRINTK_EFI` absent (removed in 6.6) → `earlyprintk=efi` was a no-op
- `CONFIG_EFI_EARLYCON` off (needs SERIAL_EARLYCON) → no `earlycon=efifb`
- `CONFIG_FB_EFI` / `CONFIG_SYSFB_SIMPLEFB` off → NO EFI framebuffer; console only
  appears once i915 KMS is up. If i915 hangs (classic Bay Trail) → dead screen.

=> Our kernel may have been booting all along, invisibly, then hanging (likely
i915) with no console to show it.

## Fix: config/debug-console.config (rebuild)

Enable `SERIAL_8250_CONSOLE` (→ SERIAL_EARLYCON → EFI_EARLYCON), `FB_EFI`,
`SYSFB_SIMPLEFB`. Then boot with `earlycon=efifb console=tty1` to SEE the boot.

## ✅ RESOLVED: kernel boots to userspace (2026-07-01)

With console options (build #3) + `earlycon=efifb console=tty1 keep_bootcon panic=0`:
- The kernel boots fully, past the i915 handoff (`bootconsole [efifb0] disabled`).
- With `init=/bin/sh` it reaches userspace and runs the shell, then:
  `Kernel panic - not syncing: Attempted to kill init! exitcode=0x00000200`
  (= /bin/sh exited; normal when init exits). Firmware confirmed:
  `Acer Iconia W4-820P/Cheetah3, BIOS v1.14 01/27/2014`.

**Conclusion: our openFyde 6.6.76 kernel (EFI_MIXED + console) boots end-to-end on
the W4-820. The 32-bit-UEFI boot problem is SOLVED.**

Root cause of the long "silent freeze": ChromeOS kernel had no EFI framebuffer/
earlycon, so a working boot was invisible; the earlier real-init "sudden reboot"
is FydeOS *userspace* (init=/sbin/init) resetting — next phase.

## Next phase: FydeOS userspace

Real `init=/sbin/init` resets (userspace reboot; panic=0 can't stop a userspace
reboot). Most-built-in drivers are =y so basic boot works, but the rootfs modules
are `6.6.99-fyde` and our kernel is `6.6.76-g...` → `/lib/modules/<our-uname>/`
missing. Plan: `make modules` + `make modules_install` → inject into ROOT-A
`/lib/modules/6.6.76-g.../` (watch ROOT-A free space). Then retry real init with
keep_bootcon to see the userspace failure point.
