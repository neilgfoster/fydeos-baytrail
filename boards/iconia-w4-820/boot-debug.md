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

## Userspace reset diagnosed (2026-07-01) — NOT a kernel problem

Kernel boots fully + modules injected. With real init it resets **~40s in**.
`oops=panic panic=0` did NOT halt it → not a kernel oops. Screenshot of the error
batch before the reboot:
- `chmod() of /usr/cache/dlc to (755) failed: No such file or directory`
- **`TPM not available`**
- `imageloader-shutdown main process (473) terminated with status 1`
- **`Failed to get ChromeOS ACPI sysfs path`**

=> This is **FydeOS/ChromeOS userspace failing on non-Chromebook hardware**: the
W4-820 has no TPM ChromeOS recognises and no ChromeOS ACPI device. The kernel work
is DONE; remaining issue is OS-image/hardware compatibility (TPM/ACPI), a different
class of problem.

dmesg-to-ESP capture wrapper (scripts/… init=/sbin/iconia-dbg) FAILED to write
because VFAT_FS=m (not loaded early). To retry capture: modprobe vfat first, or
write to an ext4 target (ext4 is built-in).

### Directions to evaluate
1. BIOS: check for a TPM / Intel PTT (fTPM) / Security Device toggle to enable.
2. Whether openFyde amd64 can run without a TPM (tpm_dynamic / simulator) — may
   need image-level changes (the full build we deferred).
3. Find the exact reboot trigger (last log line) — likely a TPM/cryptohome or a
   critical upstart job.

## ROOT CAUSE of the ~40s reset FOUND (2026-07-01)

Full dmesg captured to ROOT-A via init wrapper v3 (log to rootfs; VFAT=m broke the
ESP route). Failure chain at ~36s:
```
init: tpm2-simulator pre-start process (520) terminated with status 1
chromeos_startup: TPM not available
ERROR chromeos_startup: tpm_setup.cc:176] TPM not available.
init: imageloader-shutdown main process (530) terminated with status 1
```
openFyde ships a SOFTWARE TPM (tpm2-simulator); it failed to start because our
kernel lacked **`CONFIG_TCG_VTPM_PROXY`** (the /dev/vtpmx driver the simulator uses
to present /dev/tpm0). We built the generic x86_64 flavour standalone and missed
this board-overlay config. Fix: `config/tpm.config` (CONFIG_TCG_VTPM_PROXY=y),
rebuild. Built-in, so module vermagic unchanged → reflash kernel only, modules stay.

Note: our standalone build may miss OTHER openFyde amd64 board-overlay configs;
watch for further missing-driver failures after this.

## THE fix for the TPM reboot (2026-07-01)

Read /etc/init/tpm2-simulator.conf from the rootfs. Its pre-start runs:
```
modprobe tpm_vtpm_proxy
mkdir -p /mnt/stateful_partition/unencrypted/tpm2-simulator ; chown ...
```
`modprobe tpm_vtpm_proxy` was FAILING (exit 1) -> pre-start status 1 -> TPM not
available -> reboot. Why: we made VTPM_PROXY built-in in kernel #4/#5, but the
INJECTED rootfs modules were from build #3 (before that). So the rootfs
`modules.builtin` didn't list tpm_vtpm_proxy and no .ko existed -> modprobe can't
find it -> exit 1. The driver IS in the kernel; the module METADATA was stale.

FIX: rebuild modules against kernel #5 (`make modules && make modules_install`) so
`modules.builtin` lists tpm_vtpm_proxy, then re-inject the module tree onto ROOT-A.
Then `modprobe tpm_vtpm_proxy` returns 0 (built-in) -> pre-start OK -> TPM works.

LESSON: whenever we change the kernel config, the injected /lib/modules tree
(esp. modules.builtin/modules.dep) must be rebuilt to match, or modprobe of a
now-built-in module fails.

Other TPM init jobs present: trunksd, tpm_managerd, attestationd, vtpmd, cr50-result.

## ✅✅ FYDEOS BOOTS ON THE W4-820 (2026-07-02)

After rebuilding modules against kernel #5 (so modules.builtin lists tpm_vtpm_proxy)
and re-injecting: the tablet boots FydeOS to the OOBE/language screen with a WORKING
TOUCHSCREEN. Custom EFI_MIXED kernel + injected modules + i915 + panel + touch +
full ChromeOS userspace (TPM via tpm2-simulator) all working from USB.

Winning stack: kernel #5 (6.6.76, EFI_MIXED + VTPM_PROXY + EFI console + VFAT) via
self-built bootia32 GRUB, modules rebuilt to match + injected into ROOT-A (with the
ro-compat tamper byte cleared), on a stock FydeOS installer USB.

Remaining: finish OOBE, then install to eMMC and re-apply kernel + matching modules
to the eMMC ESP/rootfs (PARTUUIDs change; rootfs ro-compat byte must be cleared).
