# Artifact cache & the prepare-USB flow

This is the plan for turning the manual per-device work into a repeatable process:

> Bring a stock FydeOS installer USB (unknown version) → inspect it → boot it to
> diagnose the target device → resolve the right build → if it's already built,
> drop it on the USB and go; if not, build once, cache it, then go.

## Why a cache, and where artifacts live

Builds are expensive and heavy: a kernel + matching modules is ~15 min and ~210 MB.
We do **not** want to rebuild per install, and we do **not** want 200 MB tarballs in
git (or git-lfs — its free storage/bandwidth is ~1 GB, i.e. a few builds, and every
clone pays for it).

So artifacts split by where they belong:

| Kind | Example | Stored in |
|------|---------|-----------|
| Sources / config / scripts | `*.config`, `patches/*`, `install/*.{c,sh,conf}`, `boot/grub.cfg`, `audio/*` | **git** |
| Manifest (device → build) | `boards/<id>/artifacts.manifest` | **git** |
| Heavy build outputs | `vmlinuz`, `modules.tar`, compiled helpers, `bootia32.efi` | **GitHub Releases** |
| Downloaded bundles (transient) | `.artifact-cache/<tag>/` | gitignored |

GitHub Releases is already the store (`kernel-6.6.76-efimixed`, `booting-2026-07-02`);
this just formalizes it.

## Build identity — the tag

A build is identified by a **tag** = `<base>-<fingerprint>` where the fingerprint is
`sha256` of the config fragments + patches + install sources listed in the manifest's
`FINGERPRINT_INPUTS`. Change any input → new fingerprint → new tag → forced rebuild.
This is what guarantees you never silently ship a stale kernel after editing a config
fragment.

## The pieces

- `boards/<id>/artifacts.manifest` — match rule (which stock kernel this build serves),
  the tag base, the fingerprint inputs, and the release-bundle member list.
- `scripts/resolve-artifacts.sh --board <id> [--download]` — computes the tag, checks
  the release. Cache hit + `--download` → fetches `.artifact-cache/<tag>/` and verifies
  every file against the release's `bundle.sha256`. Exit 0 = hit, 10 = miss.
- `scripts/publish-artifacts.sh --board <id>` — bundles the build outputs, writes
  `bundle.sha256`, creates/updates the release under the same tag.

## End-to-end flow

```
                inspect-usb.sh  ──►  usb-profile.env   (stock kernel ver, ESP, PARTUUIDs)
                     │
   (util boot: diagnose target HW) ──► hardware-status.md / diagnostics
                     │
              resolve-artifacts.sh --board <id> --download
                 │                         │
            CACHE HIT                  CACHE MISS (exit 10)
                 │                         │
                 │        build-kernel-standalone.sh + gcc helpers
                 │        publish-artifacts.sh  (fills the cache)
                 │                         │
                 └───────────┬─────────────┘
                             ▼
     inject-kernel.sh / inject-rootfs.sh  (bundle + repo config → USB, then eMMC)
```

Install-time config (grub.cfg PARTUUID template, ALSA UCM, `chrome_dev.conf` flags,
the `install/*.sh` scripts, `soc_button_array`/`iconia-buttond` deployment) stays in the
repo and is applied by the inject/install scripts — only the build-expensive binaries
come from the release bundle.

## Status

- ✅ Manifest + resolve/publish scripts scaffolded and dry-run-verified for
  `iconia-w4-820`.
- ⬜ Publish the current 6.6.76-baytrail bundle (run `publish-artifacts.sh` once the
  build outputs are present on the build host).
- ⬜ Wire `inject-kernel.sh` to accept `--from .artifact-cache/<tag>/`.
- ⬜ The device-diagnostic util boot that auto-captures the hardware matrix (today the
  `install/iconia-*-diag.sh` scripts do this piecemeal).
