# Fix-location legend (shared across boards)

Each row in a board's `hardware-status.md` tags where its fix lives:

- **kernel** — a `CONFIG_*` change → rebuild `chromeos-kernel-*` → re-inject
  `vmlinuz`. Board-specific fragments go in `boards/<board>/config/*.config`;
  the shared 32-bit-UEFI enabler is `config/efi-mixed.config`.
- **cmdline** — a kernel parameter only. Edit the injected `/boot/grub/grub.cfg`
  `linux` line — **no rebuild**. Fastest iteration (e.g. `i915.*`,
  `acpi_backlight=`, `nomodeset`). Try these first.
- **rootfs (firmware/UCM)** — blobs under `/lib/firmware` or ALSA UCM under
  `/usr/share/alsa` live on the rootfs, not the kernel. Stage them in
  `boards/<board>/stage/` and apply with `scripts/inject-rootfs.sh`.
- **DMI/DSDT quirk** — a kernel patch matching the board (in
  `boards/<board>/patches/`), or a DSDT override at boot.
- **firmware-limited** — lives in the device's (32-bit) UEFI; the kernel can only
  work around, not fix. Suspend/S0ix and some ACPI bugs fall here.

## Applicability by device class

- **64-bit CPU + 32-bit UEFI** (Bay Trail / Cherry Trail tablets): the full
  pipeline applies. `config/efi-mixed.config` is the shared enabler.
- **Genuinely 32-bit CPU** (e.g. Clover Trail Z2760): NOT supported — a 64-bit
  FydeOS kernel cannot execute. `EFI_MIXED` is about firmware bitness, not CPU
  bitness. Check `CPU_64BIT=yes` in the board's `board.env` before starting.
