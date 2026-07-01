# Diagnostic findings

## Hardware

- **Device:** Acer Iconia W4-820
- **SoC:** Intel Atom Z3740D (Bay Trail-T), **64-bit CPU**
- **Firmware:** 32-bit UEFI only, no CSM/legacy BIOS
- **Implication:** CPU can run a 64-bit kernel, but the firmware hands off in
  32-bit mode, so both the bootloader and the kernel's EFI entry must be 32-bit.

## What the stock FydeOS installer USB contains

Partition layout is standard ChromeOS (12 GPT partitions). The EFI System
Partition is **partition 12** (32 MB, FAT):

```
efi/boot/bootx64.efi   64-bit GRUB (only UEFI loader present)
efi/boot/grub.cfg      menu; uses the ChromeOS-only `gptpriority` command
syslinux/vmlinuz.A     kernel image A  (also .B)
syslinux/*.cfg         legacy BIOS (syslinux) boot config
```

- No `bootia32.efi` → 32-bit firmware sees nothing bootable. **Fixable** by adding
  a 32-bit GRUB.
- `grub.cfg` uses `gptpriority`, which upstream/generic GRUB lacks → a generic
  `bootia32.efi` must be paired with its own `gptpriority`-free config (we place
  one at `/boot/grub/grub.cfg`, the prefix the prebuilt binary searches).

## The real blocker: kernel `xloadflags`

`xloadflags` lives at offset **`0x236`** in the kernel image (Linux boot protocol
setup header). Read on the stock FydeOS `vmlinuz.A`:

```
$ od -An -tx1 -j $((0x236)) -N 2 vmlinuz.A
 2b 00                     # = 0x002b
```

Bit decode of `0x2b` = `0010 1011`:

| Bit    | Flag                            | State |
|--------|---------------------------------|-------|
| `0x01` | `XLF_KERNEL_64` (64-bit kernel) | set   |
| `0x02` | can be loaded above 4G          | set   |
| `0x04` | **`XLF_EFI_HANDOVER_32`**       | **CLEAR** |
| `0x08` | `XLF_EFI_HANDOVER_64`           | set   |
| `0x20` | 5-level paging                  | set   |

The kernel provides only a **64-bit** EFI handover entry. A 32-bit GRUB on 32-bit
firmware has nowhere valid to jump → it enters 64-bit code with the CPU still in
32-bit mode → **instant hard freeze, no console output**.

### Observed symptom that confirmed it

With `bootia32.efi` in place the tablet reached GRUB, showed the menu, and on
boot printed `Booting a command list` (GRUB's pre-jump message) then **froze on a
static cursor with zero kernel output** — even with `earlyprintk=efi,keep` and
`console=tty1`. Zero early output ⇒ the kernel never started executing ⇒ handoff
failure, not a driver/graphics hang.

## The fix

Rebuild the openFyde kernel with:

```
CONFIG_EFI_MIXED=y              # builds the 32-bit EFI stub → sets XLF_EFI_HANDOVER_32
CONFIG_EFI_HANDOVER_PROTOCOL=y  # GRUB's `linux` loader uses the handover protocol
CONFIG_EFI_STUB=y               # dependency (normally already enabled)
```

`CONFIG_EFI_MIXED` depends on `X86_64` + `EFI` (both already satisfied). After a
rebuild, `xloadflags` should read `0x2f` (bit `0x04` set). That is the go/no-go
check before touching the tablet again.

## Working boot chain (once kernel is fixed)

```
32-bit UEFI firmware
  └─ EFI/BOOT/BOOTIA32.EFI            (32-bit GRUB 2, prebuilt)
       └─ /boot/grub/grub.cfg          (gptpriority-free; search + linux)
            └─ /syslinux/vmlinuz.A      (rebuilt kernel, XLF_EFI_HANDOVER_32=1)
                 └─ root=PARTUUID=…      (FydeOS rootfs)
```

Prebuilt 32-bit GRUB used for validation:
`https://github.com/hirotakaster/baytail-bootia32.efi` (570,880-byte i386 EFI
GRUB 2 binary; verified `PE32 executable (EFI application) Intel 80386`).
