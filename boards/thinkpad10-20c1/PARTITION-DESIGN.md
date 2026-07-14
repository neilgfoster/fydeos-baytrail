# ThinkPad 10 20C1 — ChromeOS partition-placement design

Designed T5-continuation session (2026-07-14). See `PROGRESS.md` for the session log this
came out of, and `CLAUDE.md` for the NEVER-BREAK-SSH rule that gates any actual write.

## Two-phase goal — read this before reusing any number below

This device's FydeOS bring-up is explicitly two-phase:

- **Phase A (this doc, current):** hand-place a bounded ChromeOS/FydeOS install into the
  free eMMC gap *alongside* the existing Windows partitions (dual-boot). Purpose: validate
  every piece of hardware (WiFi, Bluetooth, NFC, sensors, HDMI, buttons — see
  `hardware-status.md`) under FydeOS without giving up the only recovery path if something
  doesn't work. Windows stays fully intact throughout.
- **Phase B (future, gated on Phase A succeeding):** wipe Windows, give FydeOS the entire
  58 GB eMMC. Will very likely use a plain whole-disk `chromeos-install` at that point (no
  preservation constraint left) rather than resizing Phase A's layout in place.

**What's reusable for Phase B:** the type-GUID table, the boot-flow decision (kernel
served off the existing ESP, not a dedicated EFI-SYSTEM partition), and the
`sgdisk`-in-rescue-image tooling/procedure below.

**What's NOT reusable for Phase B:** the partition *sizes* in the table below. They're
deliberately squeezed to fit the 14.74 GB Phase-A test gap. Phase B will have the whole
58 GB disk and should size STATE/ROOT generously from scratch, not inherit these numbers.

## Reference data (pulled live, read-only, from the SD card installer clone)

The SD card (Windows Disk 1) is the existing 12-partition ChromeOS/FydeOS installer clone
(same `release-R144-16503.B` build this board targets — see `board.env`). Queried via
`Get-Partition -DiskNumber 1` over SSH (channel #1), read-only, no writes. Sorted by
offset, this is the real, exact stock layout for this build — not guesswork:

| Partition | Type GUID | Size |
|---|---|---|
| RWFW | `CAB6E88E-ABF3-4102-A07A-D4BB9BE3C1D3` | 8 MiB |
| KERN-C (stub) | `FE3A2A5D-4F32-41A7-B725-ACCC3285A309` | 512 B |
| ROOT-C (stub) | `3CB8E202-3B7E-47DD-8A3C-7FF2A13CFCEC` | 512 B |
| reserved (9) | `2E0A753D-9E48-43B0-8337-B15192CB1B5E` | 512 B |
| reserved (10) | `2E0A753D-9E48-43B0-8337-B15192CB1B5E` | 512 B |
| KERN-A | `FE3A2A5D-...` (kernel) | 16 MiB |
| KERN-B | `FE3A2A5D-...` (kernel) | 16 MiB |
| OEM | `0FC63DAF-8483-4772-8E79-3D69D8477DE4` (linux-data) | 16 MiB |
| EFI-SYSTEM (installer's own) | `C12A7328-F81F-11D2-BA4B-00A0C93EC93B` | 32 MiB |
| ROOT-B (stub) | `3CB8E202-...` (rootfs) | 2 MiB |
| ROOT-A (real payload) | `3CB8E202-...` (rootfs) | 2.72 GiB |
| STATE | `0FC63DAF-...` (linux-data, by convention) | 4.0 GiB (installer-sized, unexpanded) |

This is the canonical ChromiumOS type-GUID table, confirmed against this exact device's
own installer media rather than assumed from memory.

## Chosen approach

**Boot stays off the existing eMMC ESP (P1) — no new EFI-SYSTEM partition in the gap.**
Continues the pattern already established for channel #2 (the rescue image lives in this
same ESP) and matches `boards/iconia-w4-820/install/iconia-install.sh`'s precedent: GRUB
`linux`-boots a kernel file directly with `root=PARTUUID=<ROOT-A>`, bypassing vboot's
automatic KERN-partition kernel selection entirely. One fewer partition to hand-place next
to live Windows data.

**Otherwise, keep the standard ChromeOS partition shape (numbers/labels/types), sized
down.** FydeOS/ChromeOS userland (`chromeos_startup`, `cgpt find`, stateful-partition
lookups) generally expects to find partitions by conventional cgpt number/label/type —
safer to keep them present-but-minimal than omit them, matching the installer's own
precedent of near-zero stub sizes for the C-slots.

**Tool: `sgdisk` (GPT fdisk), not `cgpt`, for the write.**
- Definitely apt-installable (Debian `gdisk` package, confirmed this session — `cgpt`'s
  Debian availability was unconfirmed). `sgdisk` accepts raw ChromeOS type GUIDs directly
  (captured above), so its output is fully cgpt/vboot-compatible content without needing
  `cgpt` for the write itself.
- `sgdisk --backup=<file>` takes an atomic, restorable snapshot of the GPT header+table
  before any write — the concrete safety net for this step. (Protects the *partition
  table* only, not contents — real safety comes from writing exclusively inside the
  already-unallocated gap's LBA range, never touching P1–P4.)
- Sector-exact `-n <part>:<start>:<end>` / `-t <part>:<guid>` flags map directly onto the
  byte math below.

**Where it runs: inside the rescue image (channel #2), not an external host with the eMMC
pulled.** The rescue kernel already has `MMC_SDHCI_ACPI` built in and proved live block
device access (mounting the ESP, per PROGRESS.md T4). Running the write from channel #2
keeps Windows/channel #1 completely uninvolved in the risky part — the
already-independently-proven channel does the work; Windows is an unaffected bystander
since P1–P4 are never touched.

`scripts/build-rescue-image.sh` now bundles `sgdisk` into the rescue initramfs via the
existing `copy_with_libs()` pattern (same shape as `dropbear`/`wpa_supplicant`).

## Concrete partition table for the Phase-A gap

Gap: offset 36,915,118,080–52,742,324,224 (15,827,206,144 B = 14.74 GiB), confirmed
512-byte-sector-aligned (both offsets divide evenly by 512 → LBA 72,099,840–103,012,352).
Sector size (512) to be re-confirmed via `blockdev --getss` at execution time, not assumed
blind.

| # | Label | Type | Size | Rationale |
|---|---|---|---|---|
| 2 | KERN-A | kernel | 16 MiB | matches installer; unused if GRUB boots kernel-as-ESP-file (Iconia pattern), kept for shape/compatibility |
| 3 | ROOT-A | rootfs | 4 GiB | real payload; ~1.5x installer's 2.72 GiB for package growth |
| 4 | KERN-B | kernel | 16 MiB | stub slot, matches installer |
| 5 | ROOT-B | rootfs | 2 MiB | stub, matches installer exactly |
| 6 | KERN-C | kernel | 512 B | stub, matches installer exactly |
| 7 | ROOT-C | rootfs | 512 B | stub, matches installer exactly |
| 8 | OEM | linux-data | 16 MiB | matches installer |
| 9 | reserved | chromeos-reserved | 512 B | matches installer |
| 10 | reserved | chromeos-reserved | 512 B | matches installer |
| 11 | RWFW | chromeos-firmware | 8 MiB | matches installer; likely unused (Windows/Lenovo firmware stays authoritative, ChromeOS auto-update masked) but cheap to keep for shape |
| 1 | STATE | linux-data | remainder (~10.6 GiB) | bulk of the gap — user data, browser cache, Android/session state |

(Partition **numbers** intentionally follow ChromeOS convention — 1=STATE, 2/3=A slot,
4/5=B slot, 6/7=C slot, 8=OEM, 9/10=reserved, 11=RWFW — regardless of physical *order* in
the gap; ChromeOS tooling looks up by number/label via `cgpt find`, not disk order.)

No EFI-SYSTEM (12) is created in the gap — boot continues through the existing eMMC ESP
(P1), per "Chosen approach" above.

## Explicitly deferred — needs its own separate go-ahead before running

Per `CLAUDE.md`'s standing rule, none of the following happens without a fresh, explicit
plan review naming these exact commands:

1. Rebuilding the rescue image with `sgdisk` bundled in (done, see below) and re-staging
   the rebuilt `rescuex64.efi` onto the tablet's ESP — an SSH+ESP-write step.
2. Actually running `sgdisk` against `/dev/mmcblk0` (or whatever device node the rescue
   kernel assigns the eMMC) inside the rescue image to create these partitions for real —
   needs the exact `sgdisk -n`/`-t`/`-c` command sequence with final sector math, the
   `--backup` step, and a pre/post `sgdisk -p` diff confirming P1–P4 are byte-identical
   before/after.
3. Filesystem creation (`mkfs.ext4` on STATE, rootfs population on ROOT-A) and the actual
   FydeOS install — PROGRESS.md's separate "step 2."
