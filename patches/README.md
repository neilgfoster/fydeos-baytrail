# Kernel patches

Board-specific kernel patches for the Iconia W4-820 (Bay Trail) that go beyond a
plain `CONFIG_*` change — e.g. a DMI quirk table entry, a touchscreen device-props
match, an audio board-quirk, or a DSDT override.

## Conventions

- One concern per patch. Name them `NNNN-short-description.patch` (ordered).
- Patches apply against the openFyde kernel tree at
  `src/third_party/kernel/v6.6` (unified diff, `-p1`).
- Keep a one-line rationale at the top of each patch and a row in
  [`../docs/hardware-status.md`](../docs/hardware-status.md).

## How they get applied in the build

`scripts/build-kernel.sh config` (extend it as patches appear) will `git apply`
each `patches/*.patch` into `src/third_party/kernel/v6.6` before building. Until a
patch exists here, only the config fragments in `../config/` are applied.

## Nothing here yet

The first fix (EFI_MIXED) is config-only — see `../config/efi-mixed.config`. Add
patches here as hardware bring-up (Wi-Fi/audio/touch) surfaces board quirks.
