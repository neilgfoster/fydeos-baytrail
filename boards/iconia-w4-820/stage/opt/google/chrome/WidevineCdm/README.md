# Widevine CDM — rootfs bake

Bakes the Widevine Content Decryption Module (Netflix / Spotify / Disney+ etc.)
into the FydeOS rootfs so a clean re-flash has DRM playback with **no post-install
steps** (no `enable_libwidevine`, no stateful copy that a powerwash would wipe).

## What gets baked

    opt/google/chrome/WidevineCdm/_platform_specific/cros_x64/libwidevinecdm.so

Chrome loads a *bundled* CDM from `/opt/google/chrome/WidevineCdm` directly at
startup. Stock FydeOS ships that dir as an empty **stub** (a `manifest.json`
v4.10.2557.0 with no `.so`) and expects the user to run
`/usr/bin/enable_libwidevine --file <so>`, which copies the blob into
`/mnt/stateful_partition/unencrypted/widevine/...` and bind-mounts it over `/opt`
at boot. Stateful survives reboots but **NOT a powerwash / fresh install** — hence
we bake the `.so` straight into the rootfs bundled path instead.

The existing rootfs stub `manifest.json` already matches (v4.10.2557.0, arch x64,
`sub_package_path _platform_specific/cros_x64/`), so only the `.so` needs staging.

## The blob (NOT in git)

`libwidevinecdm.so` is Google-proprietary and 11 MB, so it is **git-ignored**
(see repo `.gitignore`) and not committed. Provide it locally before baking.

- File: `_platform_specific/cros_x64/libwidevinecdm.so`
- Size: 11431856 bytes
- Version: 4.10.2557.0 (x64)
- **md5: `4c9dfe80684b306b0029ef7b9db7113a`** — this is the value FydeOS's
  `enable_libwidevine` pins for x64; the bake is only valid with this exact md5.

### How to re-source it

Any FydeOS/CrOS-x64 device on which Widevine has been enabled has the blob at
`/mnt/stateful_partition/unencrypted/widevine/WidevineCdm/_platform_specific/cros_x64/libwidevinecdm.so`.
Copy it here and verify:

    md5sum libwidevinecdm.so   # must be 4c9dfe80684b306b0029ef7b9db7113a

(FydeOS also documents a download link for this pinned blob; the md5 must match.)

## Baking

`scripts/inject-rootfs.sh --board iconia-w4-820` overlays this stage tree onto
ROOT-A. Boot the **non-verified** menuentry afterwards (rootfs edits invalidate
dm-verity — already the case for this board's grub.cfg).
