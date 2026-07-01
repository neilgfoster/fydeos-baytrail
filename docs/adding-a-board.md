# Adding a new board

This repo boots/installs FydeOS on **64-bit-CPU + 32-bit-UEFI** devices (Bay Trail /
Cherry Trail tablets) by rebuilding the openFyde kernel with the 32-bit EFI handover
entry. The boot machinery is shared; per-device details live in `boards/<board>/`.

## 0. Sanity check — is the device even supported?

- **CPU must be 64-bit.** A genuinely 32-bit CPU (e.g. Clover Trail Z2760) can NOT
  run FydeOS's 64-bit kernel — `EFI_MIXED` fixes *firmware* bitness, not CPU
  bitness. Confirm `lm` in `/proc/cpuinfo`, and set `CPU_64BIT=yes` in `board.env`.
- **Firmware must be 32-bit UEFI** (otherwise you don't need any of this).

## 1. Scaffold the board dir

```
cp -r boards/_template boards/<your-board-id>
$EDITOR boards/<your-board-id>/board.env       # fill in device + build target
```

## 2. Inspect the installer USB → pin the kernel

On the FydeOS/ChromeOS host (crosh `shell`) with the installer USB plugged in:

```
sudo sh scripts/inspect-usb.sh --board <your-board-id>
```

This writes `boards/<board>/usb-profile.env` with the kernel version, `xloadflags`
(confirm bit `0x04` is CLEAR = the problem this repo solves), cmdlines and PARTUUIDs.

## 3. Pin the build target in `board.env`

From the USB kernel version (e.g. `6.6.99`), find:
- the ChromiumOS release `release-Rxx-XXXXX.B` carrying that kernel
  (browse the kernel refs in `openFyde/manifest` `chromiumos.xml` per branch), and
- the matching openFyde manifest branch `rxx-dev`, and
- the `OPENFYDE_BOARD` overlay matching the installer label.

Set `CROS_RELEASE`, `OPENFYDE_MANIFEST_BRANCH`, `OPENFYDE_BOARD`, `KPKG`.

> Boards that share a `CROS_RELEASE` share ONE `~/openfyde/src` checkout — you only
> pay the multi-GB sync once. Different releases need separate checkouts (override
> `OPENFYDE_ROOT`).

## 4. Build + inject

```
scripts/build-kernel.sh --board <board> sync      # once per CROS_RELEASE (slow)
scripts/build-kernel.sh --board <board> config    # efi-mixed + board fragments/patches
# ... enter cros_sdk and run the printed emerge commands ...
scripts/build-kernel.sh --board <board> extract   # -> boards/<board>/out/vmlinuz (want 0x2f)
sudo sh scripts/inject-kernel.sh --board <board>  # onto the installer USB
```

## 5. Bring up hardware

Boot, read `dmesg`, and fill in `boards/<board>/hardware-status.md`. Add fixes as
`boards/<board>/config/*.config` (kernel), `boards/<board>/patches/*.patch` (quirks),
`grub.cfg` cmdline tweaks (no rebuild), or `boards/<board>/stage/` +
`scripts/inject-rootfs.sh` (firmware/UCM). See
[hardware-status-legend.md](hardware-status-legend.md).
