# PROGRESS — session log & resume guide

> **Read this first when resuming.** This is a multi-session project. This file is
> the source of truth for *where we are*, *what's decided*, and *what's next*.
> Update the "Current state" and "Next actions" sections at the end of each session.

## ⚠ REPRODUCIBILITY STATUS (goal: wipe → USB → working Iconia)

**NOT yet achievable.** Every fix exists in the repo, but almost all are applied LIVE
over SSH — `boards/iconia-w4-820/stage/` (what `inject-rootfs.sh` bakes) is EMPTY, and
no install/finalize script wires in chrome_dev.conf / powertune / memtune / als-
brightness / wifi-fix / sshsetup. `iconia-emmc-finalize.sh` only re-enables UI + tidies
grub. This is the deferred "finalization" work. Recipe to close it (which fix goes to
rootfs `stage/` vs powerwash-safe `/usr/share/power_manager/`, plus the depmod/fw steps)
is captured in memory `iconia-finalization-plan`. Do it AFTER the hardware backlog (BT
etc) is closed. Acceptance test = cold-boot every row of hardware-status.md from a wipe.

## Session 16 (2026-07-08) — ARC++ TRUE root cause: KERNEL VERSION SKEW (supersedes S15 layers 3–4) ⏳ build running

**TL;DR:** Session 15's "layer 3 binfmt_misc + layer 4 StartArcMini 25s timeout" were a mis-read.
The real, single root cause of ARC not working is a **kernel/userspace version skew**: the tablet runs
a **custom 6.6.76 (ChromeOS R138) kernel** under a **FydeOS 16503 / M144 / R144 userland whose kernel is
6.6.99**. The R144 ARC runtime (`run_oci`) **SIGSEGVs** (GP fault in libc, in the post-`unshare`
android-uid child) on the R138 kernel's ashmem/container ABI → mini-container crashes ~250ms after start
→ Chrome retries → the "Android/Play wizard" spins forever. Fix = rebuild a **version-matched 6.6.99
kernel**. Built it; it boots to splash on the tablet but bootlooped once (missing matching modules —
being fixed now).

**How we got here (grounding, per user's steer):**
- ARC actually boots **on-demand**: mini-container starts then idles-down; full container + `system_server`
  only come up after **opt-in completes** (sets pref `arc.enabled`). "android-sh: PID file not found" / no
  android procs at idle is NORMAL, not breakage. `android-sh` PID lookup is broken on this build regardless.
- **GApps was a red herring.** User re-flashed **OpenGApps (Q/10)** ~08:34 → it corrupted the ARC++ `/system`
  overlay (wrong ownership/SELinux/build.prop-md5) → `arcbootcontinue` exit 1 + a `run_oci` crash. We
  **reverted it cleanly** (overlay upper is `.../unencrypted/android/root_up`; backed up to
  `/mnt/stateful_partition/gapps-root_up-20260708-1811.tar.gz` — that tarball is the BROKEN gapps, don't
  restore it). Stock "slim" `/system` has **no Play** (Play is an add-on) — that's why the opt-in wizard spins
  without it. But the deeper blocker below is kernel, not GApps.
- **Reference-device baseline (the key move):** the crosh HOST laptop runs the SAME FydeOS (slim-io / 16503 /
  M144) and **ARC works** — on the **stock `6.6.99-fyde` kernel** (`/dev/ashmem` present, `system_server`
  up, no `run_oci` crash). Only the tablet is different (custom 6.6.76). The tablet's June-29 working ARC
  (9-day uptime) was that stock 6.6.99 kernel; today's reboots into the custom 6.6.76 builds is when it broke.
- **Verified the "closed source" premise:** partly true. `git ls-remote` shows chromium openly exposes
  `release-R144-16503.B-chromeos-6.6` (=6.6.99) up to R151 — so the ChromeOS **base** kernel matching the
  userland IS open/buildable; only FydeOS's `-fyde` delta (commit `gfdc62122de5f`, not in chromium) is closed,
  and it's not the ABI-relevant layer. So 6.6.76 was never forced — it's just the branch that was checked out.

**Custom-kernel changes are small & port cleanly to 6.6.99** (checked): 2 patches
(`patches/bt-sco-transport-routing.patch`→hci_bcm.c; `patches/hid-accel-rotation.patch`→hid-sensor-accel-3d.c
[module] + drm_panel_orientation_quirks.c [built-in]) + config fragments (`config/baytrail-hw.config`,
`axp288-power.config`). Both `git apply --check` CLEAN on R144. i915 stays `=y` (the `=m` note in baytrail-hw
is superseded — `noinitrd` needs it built-in). 6.6.99 already ships working ashmem, so DROP the manual
`CONFIG_ASHMEM` add.

**What we BUILT this session (all on build host `penguin`, kernel-only — no full-OS build):**
- Fetched `release-R144-16503.B-chromeos-6.6` (=6.6.99) via `git fetch --depth 1` (shallow; the repo is a
  shallow clone so full fetch enumerates ~4M objects & stalls — always `--depth 1`, FOREGROUND, since
  background git fetch here dies exit 144). Worktree at `~/openfyde/kernel-r144`.
- Applied both patches; config = `kernel-6.6.76-working.config` → `make olddefconfig` (only 11 benign deltas,
  ashmem=y/i915=y/binder built-in). Built **bzImage 6.6.99-g7232af57f054** (10,580,992 bytes,
  sha256 `2a860cac68aa68a6439b75db7a7f761af6e1b38c7958a065b70ee5522cffff8e`).
- Deployed as a 2nd grub entry ("FydeOS R144 TEST") keeping #14 default; ESP was full so dropped `vmlinuz.ctl`
  to fit. Set default=1, rebooted → **reached FydeOS splash then bootlooped** (6.6.99 + i915=y BOOT/DISPLAY
  WORKS on Bay Trail!). **Cause: deployed vmlinuz WITHOUT its matching `/lib/modules/6.6.99-g7232af57f054/`**
  — a critical `=m` driver fails at userspace → reset. Lesson: a kernel version bump needs modules installed too.
- **Recovery:** USB auto-restore did NOT run (tablet EFI-boots the USB → normal init; the recovery script was
  on the legacy/syslinux `chromeos-usb.A` entry). User plugged an **OTG keyboard**, selected #14 at grub → booted.
  Over SSH set grub `default=0`. Tablet SAFE on #14; R144 entry + `vmlinuz.r144` still staged. **OTG keyboard is
  available now → the "no keyboard" constraint is lifted; future R144 tests keep default=0 and select at grub.**

**✅ 6.6.99 MODULES BUILT + STAGED (session end):** `make modules && make modules_install
INSTALL_MOD_PATH=/tmp/r144-mods` (EXIT_0). 366 .ko (148M) at `/tmp/r144-mods/lib/modules/6.6.99-g7232af57f054/`,
depmod done. Tarball staged to `~/MyFiles/Downloads/r144-modules.tar.gz` (sha256 `98a75c99…`) for transfer.
NOTE: this set is from `working.config` → does NOT include rotation (`hid-sensor-accel-3d`) or BT
(`hci_uart`) modules — on 6.6.76 those were built SEPARATELY from the drifted tree config; rebuild them for
6.6.99 AFTER the boot test. This 366-set matches the vmlinuz and is what's needed to boot.

**NEXT SESSION (resume here):**
1. Confirm modules build finished (`grep EXIT_0 /tmp/r144-mods-build.log`), tree at `/tmp/r144-mods/lib/modules/6.6.99-g7232af57f054/`.
2. Tar + push to tablet via Downloads share → crosh → SSH; install into `/lib/modules/6.6.99-g7232af57f054/`
   (remount rootfs rw or stage), `depmod`.
3. Reboot, select "FydeOS R144 TEST" at grub (keyboard) → verify `run_oci` NO segfault + `system_server` up +
   display/backlight OK.
4. If good: make R144 default, rebuild rotation `.ko` for 6.6.99 vermagic + redeploy, then finalization.
Full detail in memory `iconia-kernel-config-baseline`, `iconia-android-arc-diag`, `iconia-arc-setup`.

---

## Session 15 (2026-07-08) — ANDROID / ARC++ deep-dive: overlay + ashmem FIXED, houdini/timeout remain ⏳
> **NOTE (superseded by Session 16):** layers 1–2 (overlay `allow_overlayfs`, ashmem) were real & remain
> valid, but the "layer 3 binfmt_misc" and "layer 4 25s timeout" conclusions were WRONG. The true blocker is
> the 6.6.76-vs-6.6.99 kernel version skew (run_oci SIGSEGV) — see Session 16 above. binfmt_misc is not
> required (ARM apps use libnativebridge/libhoudini.so, not binfmt_misc; no houdini binary in images).

**Goal:** figure out why Android (ARC) never starts. Root-caused a 4-layer chain; fixed the
two hard kernel-level blockers and deployed them; identified the rest. Driven live over SSH
(192.168.1.31) plus an on-device Claude report (`~/fydeos-session-report-2026-07-08.md`).

**This is legacy ARC++ (container, `arcpp-*` jobs), NOT ARCVM** — needs old Android kernel
drivers on a 6.6 kernel. That mismatch is the whole story.

**Layer 1 — overlay mount blocked by kernel LSM ✅ FIXED.**
`arc-system-mount` failed every boot: dmesg `Chromium OS LSM: sb_mount Overlayfs mounts
prohibited obj=".../android/root_rw"`. The `chromiumos_security` LSM
(`security/chromiumos/lsm.c` `chromiumos_security_sb_mount`) blocks overlayfs unless the boot
flag `chromiumos.allow_overlayfs` is set (global `__setup`, default 0, read from cmdline —
NOT compiled in). Stock ChromeOS appends it via depthcharge; our **syslinux** boot never did.
Fix: added `chromiumos.allow_overlayfs` to the eMMC ESP-p12 `boot/grub/grub.cfg` cmdline
(sed after `cros_efi`). `arc-system-mount` now runs. Security note: system-wide overlayfs
relaxation (CVE-2023-0386 class) — acceptable on a single-user personal tablet, documented.

**Layer 2 — `/dev/ashmem` missing ✅ FIXED + DEPLOYED (kernel rebuild).**
Next: mini-container start hit Chrome's 25s D-Bus timeout. Real cause: `run_oci` prechroot
hook `arc-setup --mode=pre-chroot --create_tagged_ashmem` FATAL'd in 2ms —
`arc_setup.cc:2570 Failed to stat ashmem on host: No such file or directory`. Legacy ARC++
needs ashmem; mainline dropped it ~5.18; this 6.6 kernel had `# CONFIG_ASHMEM is not set`
(driver source still present at `drivers/staging/android/ashmem.c`). Module hot-load was
BLOCKED (`shmem_zero_setup` not EXPORT_SYMBOL'd → can't link/load a `.ko`), so built-in only.
Rebuilt kernel `CONFIG_ASHMEM=y`, flashed `vmlinuz.A` (sha c081b15c, 10470400 bytes, xlf 3f;
rollback `vmlinuz.A.bak-bt`=73733cc9). `/dev/ashmem` now present; prechroot succeeds <100ms.

**⚠ Bootloop + recovery (learned the config-drift rule).** FIRST rebuild attempt built off the
kernel tree's live `~/openfyde/kernel-6.6/.config` (only adding ashmem) → **early bootloop**
(reset before ICONIA banner). Cause: that tree `.config` had drifted ~100 symbols from the repo
canonical `kernel-6.6.76-working.config`, incl. `DRM_I915 y→m` (+TTM/CEC/DISPLAY_HELPER) — with
`noinitrd`, i915-as-module = no early KMS = dead boot. The `=m` entries exist only to BUILD the
hot-loaded BT/rotation modules, never to build a deployed vmlinuz. Recovered via the USB
`iconia-esp-restore.sh` (restores `bak-bt`, hash-verified). REBUILT correctly from
`kernel-6.6.76-working.config` + only `CONFIG_ASHMEM=y` → booted fine. **RULE: always rebuild
vmlinuz from `kernel-6.6.76-working.config`, never the drifted tree `.config`.** vermagic
`6.6.76-gabcfb16364e1` unchanged (MODVERSIONS off) so deployed hot-loaded modules still load.
(ESP is 32M/tight: overwrite `vmlinuz.A` IN PLACE, don't make a 2nd full-kernel backup —
`bak-bt` already == working kernel; delete partials to free space.)

**Layer 3 — `binfmt_misc` not mounted ⏳ (fix identified, live-tested, needs persistence).**
After ashmem, `arc-boot-continue` runs but `/system/bin/arcbootcontinue returned nonzero
exit_code 1 after 11ms`. Cause: all Android `/system/bin` is ARM; the houdini native-bridge
(`native_bridge is "libhoudini.so"`) can't register because **`binfmt_misc` isn't mounted**
(`CONFIG_BINFMT_MISC=y` in kernel, but `/proc/sys/fs/binfmt_misc` empty; arc-setup's
`RegisterAllBinFmtMiscEntries` fails on arm_exe/arm64_exe/arm_dyn/arm64_dyn). Binder is fine
(built-in; `/dev/binder,hwbinder,vndbinder` present). Live fix works: `mount -t binfmt_misc
binfmt_misc /proc/sys/fs/binfmt_misc` (gives register+status nodes) — needs a persistent job.

**Layer 4 — `StartArcMiniContainer` 25s D-Bus timeout RACE ⚠ (remaining, deep).**
Mini-container bring-up on this weak Atom is right at Chrome's 25s reply timeout — sometimes
succeeds (~3.9s), sometimes NoReply-times-out (`arc_session_impl.cc:519 Failed to start ARC
mini container`) → Play-ToS spinner. After failures Chrome's ARC provisioning state machine
gets stuck. NOT memory (786MB avail, no OOM). This is the legacy-ARC++-on-6.6 + slow-HW tail.

**Staged into repo this session (finalization):**
- `kernel-6.6.76-working.config`: `CONFIG_ASHMEM=y` (bake ashmem into the built kernel).
- `install/iconia-emmc-finalize.sh`: idempotently append `chromiumos.allow_overlayfs` to eMMC
  grub cmdline (same `cros_efi` sed pattern as sshsetup's `cros_debug`).
- `install/iconia-binfmt-misc.conf`: new upstart job to mount `binfmt_misc` at boot (houdini).

**Also this session (unrelated):** buttond (Windows-key→crosh) was dead after boot —
`respawn limit` boot-race (job starts before soc_button_array evdev node ready); `initctl
start iconia-buttond` fixes live; real fix = make buttond wait for the node (finalization).
Battery reporting was healthy post-reboot (acpoll running). See memory
`iconia-buttond-respawn-boot`, `iconia-kernel-config-baseline`, `iconia-android-arc-diag`.

**RESUME HERE:** wire the binfmt_misc job onto the device (or bake), re-drive Play opt-in and
watch whether the mini-container wins the 25s timeout race now paths are warm; if it keeps
losing, reduce prechroot work or accept ARC as best-effort on this 2013 Atom.

## Session 14 (2026-07-07) — WIDEVINE CDM rootfs bake (first `stage/` content) ✅

**Goal:** make Widevine (Netflix/Spotify/DRM) present by default so a clean re-flash
has it with no post-install steps — not the runtime `enable_libwidevine` toggle whose
stateful copy a powerwash/reinstall wipes.

**How FydeOS does it (learned this session):** `/usr/bin/enable_libwidevine --file <so>`
md5-checks the blob against a pinned value, copies it to STATEFUL
(`/mnt/stateful_partition/unencrypted/widevine/WidevineCdm/_platform_specific/cros_x64/`),
and `/etc/init/widevine-cdm.conf` mounts it over `/opt/google/chrome/WidevineCdm` at boot.
Stock FydeOS ships `/opt/.../WidevineCdm` as an empty stub (manifest v4.10.2557.0, no `.so`).
Chrome loads a *bundled* CDM from that `/opt` path directly — so baking the `.so` into the
rootfs bundled path needs no stateful, no toggle, survives powerwash.

**Done:**
- Confirmed on the Iconia (192.168.1.31): Widevine currently WORKING (`enable_libwidevine
  --status` = yes); blob present in stateful. Pulled it off the device.
- Verified artifact: `libwidevinecdm.so`, 11431856 bytes, x64, **md5
  `4c9dfe80684b306b0029ef7b9db7113a`** (== FydeOS's pinned x64 value).
- Staged at rootfs-mirrored path for `inject-rootfs.sh`:
  `boards/iconia-w4-820/stage/opt/google/chrome/WidevineCdm/_platform_specific/cros_x64/libwidevinecdm.so`
  — the **first real content in `stage/`**, starting to close the finalization gap.
- Blob is git-ignored (proprietary + 11 MB, consistent with "no heavy blobs in git");
  tracked `README.md` beside it documents md5 + how to re-source. `.gitignore` updated.

**Left / caveats:** not yet exercised via an actual `inject-rootfs` USB build+reinstall
(that's the deferred finalization step — see reproducibility banner). When finalization is
wired, decide whether the blob becomes a resolved release asset (like the kernel bundle)
rather than a manual local drop. Bake requires the non-verified menuentry (verity already
broken on this board).

## Session 13 (2026-07-07) — AC/BATTERY REPORTING + POWER DRAIN ✅

**Symptom:** device reported correct power/AC state only at boot, then froze; tray icon
stuck. Hidden underneath: a ~50 IRQ/s interrupt storm draining power (kept SoC out of C7S).

**Root cause (DSDT-disassembled + confirmed on-device):** AC/battery is a ULPMC-style
embedded controller on the fragile Bay Trail **i2c-0** (`\_SB.I2C1`) bus, accessed by AML
via GenericSerialBus OpRegions (`ADP1._PSR` reads `I2C1.ACDF`, not the Crystal Cove PMIC).
A level-triggered ACPI GPIO event **`GPO2._L12`** (GpioInt pin `0x12`=18 on INT33FC:02)
calls `I2C1.BATC.INTR()` to read+clear the EC IRQ. That i2c-0 read kept timing out
(`i2c_designware 80860F41:00: timeout waiting for bus ready`) → EC IRQ never cleared →
level GPE re-fired ~50/s forever, and the flood **starved the bus** so `_PSR`/`_BST`
polling also failed → frozen AC/battery. Storm caused the freeze. (i2c-0 has no scl-gpios
recovery — `No GPIO consumer scl found` — so once wedged it stays wedged; controller
unbind/bind did NOT recover it.)

**Fix (two parts, both persistent + in repo):**
1. Kernel cmdline `gpiolib_acpi.ignore_interrupt=INT33FC:02@18` — mutes the storming GPIO
   event (`byt_gpio INT33FC:02: Ignoring interrupt on pin 18`). Added to the ACTIVE
   `<ESP p12>/boot/grub/grub.cfg` line 11 (backup `grub.cfg.bak-gpe`). Result: IRQ storm
   gone, 0 bus timeouts, battery gauge live, AC correct on read.
2. `iconia-acpoll` upstart job — muting the event also removed the only power_supply
   push-notify (0 udev change events on plug/unplug), so powerd/tray only updated on a
   slow erratic internal poll. Job does `udevadm trigger --action=change` on power_supply
   every 5s → tray tracks plug/unplug within ~5s. Files:
   `install/iconia-acpoll.{sh,conf}` + `iconia-acpoll-install.sh`; live at
   `/usr/local/sbin/iconia-acpoll` + `/etc/init/iconia-acpoll.conf`.

**VERIFIED end-to-end:** multi-cycle plug/unplug tracked; storm=0; user confirmed tray
follows (few-seconds delay = the 5s poke cadence, tunable).

**Finalization follow-up:** bake the cmdline flag into the reproducible grub cmdline and
the `iconia-acpoll` job into `stage/` when the finalization pass happens.

## Session 12 (2026-07-07) — SCREEN AUTO-ROTATE ✅ (the original problem)

The device's founding bug — screen 90° out — is **FIXED, and auto-rotate works** in
all four orientations. Done via a hot-loadable **module**, NO risky vmlinuz rebuild.

- **Accel driver patch** (`patches/hid-accel-rotation.patch`, reworked): the accel is
  `CONFIG_HID_SENSOR_ACCEL_3D=m`; with `setlocalversion --no-dirty` the vermagic stays
  `6.6.76-gabcfb16364e1`, so a rebuilt `.ko` hot-loads on the running kernel. Patched
  `hid-sensor-accel-3d.c` to **hardcode** mount matrix `0,-1,0; 1,0,0; 0,0,1` (90° about
  Z; sign verified upright on-device) + `label=accel-display`/`location=lid`/samp_freq
  list so ChromeOS ash/iioservice consumes it like a cros-ec accel.
- **Dropped the SSDT** (`initramfs/ssdt-accel-mtx.{asl,aml}` deleted): it put
  `mount-matrix` `_DSD` on the ACPI I2C-HID node, which the child MFD platform device
  never inherits, so `iio_read_mount_matrix()` fell back to identity — the real flaw in
  the old kernel-#12 attempt. Also: the earlier brick was the *deploy* (ESP-full →
  truncated vmlinuz), not proof the kernel was bad.
- **Userspace route confirmed DEAD END:** ChromeOS iioservice reads the read-only kernel
  sysfs `in_accel_mount_matrix`, NOT the freedesktop `ACCEL_MOUNT_MATRIX` udev prop; no
  ACPI configfs for a runtime SSDT. Must be the module.
- **Deploy:** `install/iconia-accel-rotation-install.sh` (push `out/hid-sensor-accel-3d.ko.gz`
  → tree + depmod + reboot). sha `fa13192f…`.
- **Mode:** removed `--force-tablet-mode` entirely — device is a convertible
  (form-factor=CHROMESLATE, is-lid-convertible=true), boots **laptop**, FydeOS
  Laptop/Tablet toggle switches to tablet (auto-rotates). No FydeOS pref for
  "tablet-default + keep toggle"; is-lid-convertible=false didn't move the default →
  reverted to true. `iconia-desktop-mode-install.sh` rewritten to strip the force flag.
- **Still OPTIONAL:** DRM `panel_orientation` quirk (same patch, `CONFIG_DRM=y` built-in)
  fixes only the *base/boot* orientation (boot splash + landscape-at-login), worked
  around by manual Settings→Displays→Orientation=90° in laptop mode. Needs a vmlinuz
  rebuild → **USB smoke-test standalone before eMMC `vmlinuz.A`**. Auto-rotate doesn't
  need it. All session-12 changes are still LIVE edits (finalization gap unchanged).

## Session 10 (2026-07-05) — permanent DESKTOP (clamshell) UI

User decision: the Iconia should **always present the desktop/clamshell UX** (windowed
apps, shelf, no forced tablet shell) in **every** orientation, even used bare as a
tablet. This supersedes the earlier "leave tablet mode only when a monitor+kbd is
attached" backlog idea.

- **Change:** `/etc/chrome_dev.conf` `--force-tablet-mode=touch_view` → `=clamshell`.
  `--enable-virtual-keyboard` kept so the OSK still pops with no physical keyboard.
- **Applied live** over SSH + confirmed working on-device ("all good").
- **Install script:** `install/iconia-desktop-mode-install.sh` (idempotent; `revert`
  arg restores `touch_view`). Run: `ssh -i /tmp/ik root@192.168.1.31 'sh -s' < it`.
- Still a LIVE edit (chrome_dev.conf not yet baked into `stage/`) — finalization gap
  unchanged; the finalizer must bake `--force-tablet-mode=clamshell` now (not touch_view).

### Session 10 — microSD ✅ + shutdown fade-to-white ⚠ (partial, accepted)

- **microSD ✅ WORKS** — tested by user, marked in hardware-status.md. No work needed.
- **Shutdown "fade to white" ⚠ PARTIAL FIX (accepted "good enough").** User's real goal:
  don't get blinded at night. Root cause: the bright white is **ash's shutdown animation,
  compiled into Chrome**, which plays BEFORE any external hook — ChromeOS does the
  animation FIRST, then issues the shutdown request. Verified exhaustively over SSH:
  * No `/dev/fb0` (i915 has no fbdev). Backlight = `/sys/class/backlight/intel_backlight`
    (brightness/bl_power). `stop powerd; echo 0>brightness` DOES darken the panel (proven:
    a 10s-hold test held the screen solid black).
  * powerd `stop on stopping boot-services` (= at `starting pre-shutdown`), so a job on
    `starting halt` that waits for Chrome to exit then stops powerd + blanks WORKS for the
    post-animation tail — but the animation is already done by then (log showed chrome
    exits ~1.4-2s in; final `bl_power=4 bright=0` set, screen went dark — user saw "long
    pause on dark screen" = the blank working).
  * `runlevel` returns empty mid-shutdown → a runlevel guard silently skipped the job;
    fixed by triggering on `starting halt or starting reboot` (shutdown-only, no guard).
  * `--disable-login-animations` flag: tried, **no effect** on the shutdown animation.
    No animation-disable switch found in the chrome binary strings.
  * **Conclusion:** the ~1s white flash is un-removable without rebuilding Chrome (not
    worth it). **Accepted solution = two parts:** (1) `install/iconia-shutdown-black.conf`
    Upstart job kills the lingering white tail during unmount (fires on halt/reboot →
    wait chrome exit → stop powerd → frecon black → hammer backlight off). (2) Lowered the
    **ALS night floor 15%→5%** in `iconia-als-brightness-install.sh` so at night the flash
    rides a near-black backlight = dim, not blinding. User: "good enough."
  * Both are LIVE (job in `/etc/init/`, ALS in `/var/lib/power_manager/`) — finalizer must
    bake the job into `stage//etc/init/` and the ALS floor into the powerd defaults.

## Session 9 (2026-07-05) — BT HFP mic (SCO): kernel fix built, awaiting live test

Chose the **kernel-patch** route over an SSDT `_DSD` overlay. `hci_bcm.c`
`bcm_serdev_probe` now forces `pcm_int_params={01,00,00,00,00}` (SCO routing = HCI
transport) when ACPI HID==`BCM2E3F` and firmware/`_DSD` supplied none. Why this beats
the session-8 runtime `hcitool` poke: `bcm_setup()` re-sends the PCM params on **every**
`hci_dev_open`, so it re-applies after Floss's re-init/HCI_Reset — the poke was lost only
because Floss's re-open re-downloaded firmware *without* the param.

- Patch: `patches/bt-sco-transport-routing.patch`. Rebuilt module `out/hci_uart.ko.gz`
  (vermagic `6.6.76-gabcfb16364e1` — hot-loads on the deployed #11 kernel, no full swap).
- Deploy/verify: `install/iconia-bt-sco-{deploy,verify}.sh`. Deploy drops the module in
  the tree + `depmod` + reboot (routing applies at hci0 bring-up, before Floss owns it).
- **Must be pushed from the CROSH HOST** — Crostini (build container) can't reach the LAN
  (NAT), only the crosh host can ssh 192.168.1.31. Corrected a wrong "tablet offline"
  read this session (it was just the NAT).
- **TESTED & REVERTED.** Patch loaded (dmesg `iconia: forcing SCO routing`, hci0 UP), but
  no HFP node appeared (buds stay A2DP-only until an app opens the mic) AND forcing
  routing=transport with all-zero PCM bytes on every open **broke the whole audio path**
  (internal speaker + YouTube dead). Rolled back via the `${module}.bak.*` copy → reboot →
  audio restored. Blunt kernel-default is the wrong approach.
- Confirmed: **random BD address per boot** → buds must be forgotten + re-paired after
  every reboot (no `BCM4324B3.hcd`). Independent of this patch.
- **Next options:** (a) SSDT `_DSD brcm,bt-pcm-int-params` overlay through the kernel's
  normal ACPI-property path with properly-tuned (non-zero) PCM bytes, applied only when
  HFP negotiates; or (b) **park HFP mic as a known limitation** — A2DP out works, internal
  mic works for local capture; HFP mic is low-value on this 2013 tablet.

### Session 9 addendum — internal mic also broken (parked)

Chasing HFP mic surfaced that the **internal mic never worked either**. Card
`bytcr-rt5640` runs an **AVS DSP topology**; capture yields zero frames — raw
`arecord` → immediate `Input/output error`, `cras_test_client` capture **hangs**.
Not a mixer/UCM gap (enabling the full analog chain didn't help); it's a
driver/DSP capture-pipeline problem. **Parked** — both mics are now documented
known limitations. **Recommendation: pivot to finalization** (make fixes survive a
reinstall — the higher-value gap) rather than deep-diving mic topology on a 2013 tablet.

## Session 8 (2026-07-05) — BLUETOOTH (mostly done; HFP mic pending)

**Result: `hci0: UP RUNNING`. Pairing + A2DP audio out + AVRCP controls all work.**
Root cause was **kernel config, not the missing .hcd** (the standing hypothesis).

- **Diagnosis** (`boards/iconia-w4-820/install/iconia-bt-{survey,probe2}.sh`, read-only over SSH): BCM BT is
  onboard on the Bay Trail HS-UART — ACPI `BCM2E3F` (`\_SB.URT1.BTH0`) under `80860F0A`.
  No `hci0` because (a) `SERIAL_DEV_BUS` off → no serdev bus, (b) `BT_HCIUART` not built,
  (c) the ACPI HS-UART had **no ttyS** — `SERIAL_8250_LPSS=y` was set but that's the
  PCI variant; the ACPI `80860F0A` node needs **`SERIAL_8250_DW`** (was off).
- **Fix**: enabled in `~/openfyde/kernel-6.6/.config` + rebuilt (#11):
  `SERIAL_8250_DW=y`, `SERIAL_DEV_BUS=y`, `BT_HCIUART=m` + `_SERDEV` + `_BCM`
  (`BT_BCM=m` already on). After reboot: `dw-apb-uart 80860F0A:00 → ttyS0`, serdev
  `serial0-0` enumerates, `hci_uart_bcm` auto-binds via ACPI, btbcm IDs the chip
  **BCM4324B3** (chip id 84) — the BT half of the same BCM4324 combo as wifi.
- **Deploy over SSH** (not the old USB PID-1 path): new `vmlinuz`→eMMC ESP `vmlinuz.A`
  (xloadflags 3f 00; old backed up as `vmlinuz.A.bak-bt`) + `hci_uart.ko.gz`/`btbcm.ko.gz`
  →module tree + on-device `depmod`. Script `boards/iconia-w4-820/install/iconia-bt-deploy.sh`; artifacts
  staged in `~/openfyde/bt-deploy/`.
- **FydeOS uses Floss** (`btmanagerd`), NOT BlueZ. So BlueZ CLI (btmgmt/hcitool) fails
  with "Invalid Index/Device busy" — Floss owns hci0 exclusively (HCI user-channel).
  Test Bluetooth through the **ChromeOS UI**, not BlueZ tools.
- ⏳ **HFP mic (SCO) — NOT working yet.** CRAS shows the `BLUETOOTH_NB_MIC` node and
  selects it, but capture is 0 bytes with no `sco_conn` in dmesg. Cause: BCM4324B3
  defaults SCO audio to its **hardware PCM/I2S pins** (not wired to the RT5640 here).
  Proved the chip **accepts** `Write_SCO_PCM_Int_Param` (vendor `0xFC1C`, routing=01
  transport) with **status 0x00** — but Floss's HCI-reset reverts it; doesn't persist,
  and the manual poke left BT unstable (reboot restores). Experiment:
  `boards/iconia-w4-820/install/iconia-bt-sco-hci.sh`.
- **Next session (mic)**: send that proven vendor cmd at driver init, BEFORE Floss —
  via ACPI `_DSD brcm,bt-pcm-int-params` (SSDT overlay on BCM2E3F, which mainline
  hci_bcm reads) or a small kernel patch defaulting bcm serdev PCM routing to transport.
  Separately, no `brcm/BCM4324B3.hcd` (no Windows driver to extract) → random BD address
  per boot; pairings may not survive reboot — verify, may need a fixed-address workaround.
- **Reproducibility**: the #11 kernel + serdev/UART config must fold into the finalization
  build (kernel artifact bundle + stage/). BT needs nothing in `stage/` beyond the kernel
  (serdev auto-binds); the mic fix (once found) does.

## Session 7 (2026-07-05) — MEMORY OPTIMIZATION (2 GB device)

**Goal: run lean on 2 GB. Chrome is the whole story (~25 renderers); ARC not running.**

- **Survey:** MemTotal 1861 MB; at rest ~863 MB avail, zram 0 used (not starving — goal
  is headroom under tab load). AnonPages 633 MB, Cached 777 MB reclaimable. Chrome ≈
  2189 MB summed RSS across ~25 procs (RSS overcounts shared). **ARC/Android NOT
  running** — only idle stubs (~28 MB); no VM to reclaim. Tool: `install/iconia-mem-survey.sh`.
- ✅ **zram lz4 → zstd** (kept 3723 MB size; ~30% more pages per RAM under pressure) +
  `vm.swappiness=100`, `min_free_kbytes=8192`, `page-cluster=0`. Persistent via
  `install/iconia-memtune.{sh,conf}` boot job (runs AFTER ChromeOS builds zram, converts
  it; idempotent, only when zram empty — ChromeOS rebuilds it lz4 each boot so the job is
  required for persistence). Milestone: Chromium 144 / FydeOS 16503.20.22.10.
- ✅ **Chrome low-RAM flags** in `/etc/chrome_dev.conf` (Moderate profile, user choice —
  site isolation KEPT): `--enable-low-end-device-mode` (smaller caches + background-tab
  purge) + `--renderer-process-limit=8`. Verified live in browser cmdline; NO
  `--disable-site-isolation` (isolation intact). avail ~863→1227 MB, used 807→527 MB,
  chrome procs 25→14. Persists via chrome_dev.conf automatically (no boot job). Needs a
  one-time `restart ui`. `install/iconia-chrome-memtune-install.sh` (revert arg).
- No TLP-style whole-system tools (ChromeOS/resourced owns memory pressure + tab
  discarding; the old `chromeos-low_mem/margin` sysfs knob is gone in M144).

## Session 6 (2026-07-05) — POWER OPTIMIZATION (largely done)

**Outcome: the device already sips power; the meaningful, UX-safe wins are banked.**

- **Meter reality (important for next time):** battery ACPI gauge is **1%-quantized and
  freezes at 100%** → useless for fast A/B. Use **RAPL** `/sys/class/powercap/intel-rapl:0/energy_uj`
  for SoC-side A/B (fast, precise); battery %/time only for the screen (slow). Scripts:
  `install/iconia-pwr-rapl.sh` (SoC), `iconia-pwr-sample.sh`/`iconia-batlog.sh` (battery),
  `iconia-pwr-survey.sh` (inventory).
- **Baseline:** SoC `package-0` ≈ **0.30 W idle**, parked in **C7S** (deepest C-states
  already optimal — Bay Trail C6 bug not biting), governor **schedutil**. So CPU-side
  headroom is basically nil; the screen is the only big lever.
- ✅ **Adaptive brightness (the real win):** ALS is live + powerd-tagged; enabling
  `has_ambient_light_sensor=1` + `internal_backlight_als_steps` curve (in
  `/var/lib/power_manager`, stateful/persistent) turned fixed 63–100% into ambient-
  adaptive (~7/100 indoor). `install/iconia-als-brightness-install.sh` (revert arg).
  NOTE pref name is `internal_backlight_als_steps` (not `..._ambient_light_steps`).
  iioservice DOES broker the ALS to powerd here (unlike parked auto-rotate).
- ✅ **`disable_idle_suspend=1`** (`install/iconia-powertune.sh`, upstart-persistent):
  s2idle resume is broken (screen won't wake), and powerd would idle-suspend at 6m30s
  on battery → hang. Now screen-offs on idle (saving) but never suspends.
- **Charging icon / battery cap = firmware-limited.** PMIC is **Crystal Cove
  (INT33FD), not AXP288** — no mainline Crystal Cove charger driver; ACPI `ADP1/online`
  frozen 0 even while charging. Tried the AXP288 charger/fuel-gauge/extcon modules
  (built + hot-loaded) — wrong chip, bind to nothing. Parked. (charging *works*, only
  the bolt/status reporting is broken.)
- **Trims that were noise (power) but done anyway:** eMMC I/O sched already `none`;
  unloading dead motion sensors = within noise; stopping unused services
  (camera/cupsd/modemmanager/fwupd/p2p/avahi/update-engine) = ~**26 MB RAM** freed
  (a memory-backlog win, not power) — folded into `iconia-powertune.sh`.
- **Backburner:** rigorous brightness→mA sweep (needs ~1 h idle; battery gauge is slow).
- **Aside captured:** make shutdown fade to black not white (memory note).

## Goal

A repeatable process to boot & install FydeOS/openFyde on an **Acer Iconia W4-820**
(64-bit Bay Trail CPU, **32-bit UEFI** firmware):

1. **inspect** a stock FydeOS installer USB → kernel version, `xloadflags`, cmdlines.
2. **build** a custom openFyde kernel with `CONFIG_EFI_MIXED` (adds the 32-bit EFI
   handover entry the stock kernel lacks).
3. **inject** the kernel + `bootia32.efi` + clean `grub.cfg` back onto the USB, boot,
   then install to eMMC.

## Environment facts (so we don't re-derive them)

- Work happens from a **FydeOS device** running a **Crostini** (Debian 12) container.
- The Crostini container is the build host: **~120 GB free disk, 29 GB RAM, 8 CPU** —
  enough for a kernel-only openFyde build. `gh` is authed as `neilgfoster`.
- The installer USB is **only visible to the ChromeOS/crosh host**, not to Crostini.
  So: `inspect`/`inject` run in **crosh `shell`**; `build` runs in **Crostini**.
- In crosh, the USB enumerates as `sd?` and moves letters between replugs
  (seen as both `sda` and `sdb`). The ESP is **partition 12** (32M FAT).

## Key technical fact (the crux)

`xloadflags` @ offset `0x236` of the kernel image. Bit `0x04` = `XLF_EFI_HANDOVER_32`.
- Stock FydeOS kernel = **`0x2b`** → bit CLEAR → **won't boot** on 32-bit UEFI.
- Need a rebuild reading **`0x2f`** (bit set). This one byte is the go/no-go test.

Full reasoning: [`boards/iconia-w4-820/findings.md`](boards/iconia-w4-820/findings.md).

## Milestones

| # | Milestone | State |
|---|-----------|-------|
| 1 | Confirm USB is 64-bit-UEFI-only | ✅ done |
| 2 | Add `bootia32.efi` + clean grub.cfg; reach GRUB on tablet | ✅ done |
| 3 | Diagnose kernel freeze → missing `XLF_EFI_HANDOVER_32` (`0x2b`) | ✅ done |
| 4 | Scaffold repo + inspect/inject/build scripts | ✅ done |
| 5 | Sync openFyde, pin board + kernel package + config path | 🟡 kernel ver pinned (6.6.99-fyde); tree not synced |
| 6 | Build kernel with EFI_MIXED; verify handover bit | ✅ done — **`xloadflags=0x3f`** (6.6.76, trimmed) |
| 7 | Inject to USB; boot tablet past the freeze | ✅ **DONE** — kernel boots to userspace (init=/bin/sh) |
| 7b | FydeOS userspace boots (real init) | ✅ **DONE** — boots to OOBE, touchscreen works! |
| 8 | Install to eMMC; re-inject kernel+modules to eMMC; standalone boot | ✅ DONE — eMMC boots FydeOS to OOBE standalone (USB removed) |

## Open questions / unknowns to resolve

- **openFyde manifest branch** to pin (`MANIFEST_BRANCH`) — match the kernel version
  the installer USB actually ships (get it from `inspect-usb.sh` → `KVER_A`).
- **Exact board name**: `amd64-generic` vs a FydeOS-specific board (USB label was
  `amd64-fydeos_slim`). Confirm in the synced tree.
- **Kernel package name** (`chromeos-kernel-<ver>`) and the **config fragment path**
  under `src/third_party/kernel/v*/chromeos/config/`. `build-kernel.sh config`
  auto-discovers these into `build.env`; verify them.
- Whether `cros_sdk` runs cleanly inside Crostini (mount/namespace ok — `unshare`
  test passed — but the SDK chroot may need more).

## Current state (update me each session)

- **As of:** 2026-07-01
- Repo scaffolded; scripts written. **Inspection RUN against real USB** →
  results captured in [`boards/iconia-w4-820/usb-profile.env`](boards/iconia-w4-820/usb-profile.env).
- **Installer kernel = `6.6.99-fyde-09011-gfdc62122de5f-dirty`, built 2025-12-15.**
  Confirmed `xloadflags=0x2b` (no 32-bit handover) on both A and B slots.
- `bootia32.efi` + `grub.cfg` were manually placed on the USB earlier and confirmed
  to reach the kernel-handoff freeze. `inject-kernel.sh` reproduces that placement.
- **Repo restructured multi-board**: shared machinery (`scripts/`, `config/efi-mixed.config`,
  `docs/`) + per-device `boards/<id>/` (W4-820 = `boards/iconia-w4-820/`). All scripts
  take `--board <id>`. New devices: `docs/adding-a-board.md`, `boards/_template/`.
- **ABANDONED the full `repo sync` approach.** It pulled ~94G of the ChromiumOS
  tree (to build ONE kernel), the Chromium browser project had a bad ref
  (`openfyde-r138-dev` missing) that aborted the sync before the kernel checkout,
  and the working-tree checkout **filled the 128G disk to 100%**. Killed it and
  `rm -rf`'d `~/openfyde/src` → back to 117G free.
- **PIVOT WORKED: minimal standalone kernel build (Option A).** No `cros_sdk`, no
  94G tree — just the kernel git (1.8G) built with plain `make`. Steps that worked:
  1. `git clone --depth 1 --single-branch -b release-R138-16295.B-chromeos-6.6`
     `https://chromium.googlesource.com/chromiumos/third_party/kernel ~/openfyde/kernel-6.6`
     → 1.8G, 84k files, includes `chromeos/scripts/prepareconfig`. **Kernel = 6.6.76**
     (note: USB shipped 6.6.99-fyde — sublevel mismatch; modules won't match, OK for
     boot test; revisit r144-dev if we need 6.6.99).
  2. `CHROMEOS_KERNEL_FAMILY=chromeos chromeos/scripts/prepareconfig chromiumos-x86_64-generic`
     (the flavour the openFyde amd64 board uses; only the `reven`/ChromeOS-Flex
     flavour ships EFI_MIXED by default — confirms why stock was 0x2b).
  3. Append `config/efi-mixed.config` (EFI_MIXED + HANDOVER_PROTOCOL + STUB) to `.config`.
  4. `make olddefconfig` → **all three survived** (verified in expanded 7908-line config).
  5. Toolchain: **plain gcc works** (no CLANG/CFI/LTO forcing in this config). Installed
     `build-essential bc bison flex libssl-dev libelf-dev cpio kmod rsync`.
  6. Applied `boards/iconia-w4-820/config/trim.config` (drop nouveau/media/virtio-gpu/
     infiniband) to cut build time; essentials + EFI_MIXED verified intact.
  7. `make -j8 bzImage` (gcc) → **SUCCESS**. `arch/x86/boot/bzImage` = 10.3MB,
     **`xloadflags=0x3f` (HANDOVER32 SET)** vs stock `0x2b`. Version
     `6.6.76-gabcfb16364e1 #2`. Copied to `boards/iconia-w4-820/out/vmlinuz` and
     published as GitHub release asset `kernel-6.6.76-efimixed`.
  Build host: `~/openfyde/kernel-6.6`. Logs: `~/openfyde/logs/`. Build ~15 min trimmed.
  NOTE: version `6.6.76` (no `-fyde`) ≠ rootfs modules `6.6.99-fyde` → modules won't
  load; fine for boot test (essentials built-in). Revisit for full HW support.

## Build target — PINNED

openFyde layers on the **upstream ChromiumOS manifest** via `local_manifests`
(NOT a direct init of the openFyde manifest — that only has 21 overlay projects):

```
repo init -u https://chromium.googlesource.com/chromiumos/manifest.git \
  --repo-url https://chromium.googlesource.com/external/repo.git \
  -b release-R138-16295.B
git clone https://github.com/openFyde/manifest.git openfyde/manifest -b r138-dev
ln -snfr openfyde/manifest .repo/local_manifests
repo sync -j"$(nproc)"
```

- **ChromiumOS release: `release-R138-16295.B`** (upstream base).
- **openFyde manifest branch: `r138-dev`** — overlays via local_manifests. Verified:
  296 projects total, incl. `src/third_party/kernel/v6.6` @ `8df27f5…` (R138 chromeos-6.6),
  matching the USB's 6.6.99-fyde kernel (Dec 2025). Fallback: r144-dev / R144-16503.B.
- **Board: `amd64-openfyde_slim`** — CONFIRMED (overlay repo `overlay-amd64-openfyde_slim`
  exists; matches USB label `amd64-fydeos_slim`).
- Kernel package: `chromeos-kernel-6_6`. Config fragment appended to
  `src/third_party/kernel/v6.6/chromeos/config/x86_64/common.config`.
- Tree location: `$HOME/openfyde/src`. Sync logs: `$HOME/openfyde/logs/`.

### ⚠️ Module-version caveat (handle at inject/boot stage)

The rootfs on the USB carries modules for `6.6.99-fyde`. Our rebuilt openFyde
kernel may report a slightly different `UTS_RELEASE` (e.g. `6.6.x-openfyde` or no
`-fyde`), so `/lib/modules/<ver>/` won't match → modules won't load. For the FIRST
boot test that's OK (goal is just to get *past the EFI freeze*; essential drivers
are built-in). To fully match, either set `CONFIG_LOCALVERSION` to reproduce
`-fyde` and match the sublevel, or rebuild/replace the rootfs modules. Note the
booted kernel version once it comes up and reconcile then.

---

## ⭐ RESUME HERE — status as of 2026-07-02 (end of session 1)

**FydeOS BOOTS on the Acer Iconia W4-820 from USB — reached the OOBE/language screen
with a working touchscreen.** The core project goal (custom kernel boots a 32-bit-UEFI
Bay Trail tablet) is DONE. NOTE: the full `repo sync` / `cros_sdk` approach above was
ABANDONED — we build the kernel STANDALONE (see below). Ignore the stale "Build target"
and repo-sync notes above; the standalone recipe is the source of truth.

### The winning setup (all durable in the repo + release `booting-2026-07-02`)
- **Kernel**: openFyde R138 kernel git (`~/openfyde/kernel-6.6`, tag 6.6.76), built
  STANDALONE with plain `make` (no cros_sdk). Exact config saved at
  `boards/iconia-w4-820/kernel-6.6.76-working.config`. Config = generic x86_64 flavour
  + these fragments (in `boards/iconia-w4-820/config/` + shared `config/efi-mixed.config`):
  `efi-mixed` (EFI_MIXED+HANDOVER+STUB), `trim` (drop nouveau/media), `debug-console`
  (SERIAL_8250_CONSOLE→EFI_EARLYCON, FB_EFI, SYSFB_SIMPLEFB), `tpm` (TCG_VTPM_PROXY),
  `debug-capture` (VFAT/NLS builtin). xloadflags = **0x3f**. Artifact:
  `boards/iconia-w4-820/out/vmlinuz`, sha `2c42d429…`.
- **Bootloader**: self-built i386-efi GRUB core via `scripts/build-grub-ia32.sh`
  (`bootia32.efi`, prefix `/boot/grub`, ~512K). Reads `/boot/grub/grub.cfg` on the ESP.
- **Modules**: rebuilt to MATCH the kernel config (`modules-6.6.76-v5.tar`, sha
  `059c710f…`) and injected into ROOT-A. CRITICAL: modules.builtin must list
  tpm_vtpm_proxy or `modprobe tpm_vtpm_proxy` in tpm2-simulator pre-start fails.
- **Rootfs write access**: clear the ext ro-compat tamper byte —
  `dd if=/dev/zero of=<ROOT-A> bs=1 seek=1127 count=1 conv=notrunc` — then mount `-t ext4` rw.
- **grub.cfg** (production, i915 flicker fixes): `boards/iconia-w4-820/boot/grub.cfg`.

### Debugging harness that worked
- Can't interact with tablet (OTG keyboard dead). Capture boot via an init wrapper
  (`init=/sbin/iconia-dbg`) that dumps `dmesg` — the rootfs-write variant reached 36s;
  root cause found by reading `/etc/init/tpm2-simulator.conf` statically.
- USB↔laptop transfer: Crostini home is visible to the crosh host at
  `/media/fuse/crostini_1910d1979a76c12e132e98ff6ca5833087b4d2ce_termina_penguin/`
  (writable both ways — used it to pull `kern-a.bin` from the host too).
- All work: `inspect`/`inject` in crosh `shell`; kernel/module BUILD in Crostini.

### Flicker fix — CONFIRMED (session 2, 2026-07-02)
- Production grub.cfg with **i915.enable_psr=0 enable_fbc=0 enable_dc=0** written to
  USB ESP (`/dev/sda12`, part 12) and verified by SHA
  (`9f62151bc57c39afd366a8bdf6f203ddae3d930376502b9d0851196bf75aae09`, matches repo
  `boards/iconia-w4-820/boot/grub.cfg`). Booted on tablet → **no flicker, much smoother.**
  Bay Trail PSR was the cause. This grub.cfg is the production baseline going forward.
- Slowness is partly inherent (2GB + running off slow USB) — eMMC install will help.

## ⭐ SESSION 2 — status as of 2026-07-02

**Flicker FIXED and eMMC INSTALL DONE.** FydeOS is installed to the tablet's
eMMC and the firmware boots OUR GRUB from it. Remaining wart: the kernel's eMMC
enumeration is intermittent, so eMMC boot succeeds only ~1-in-3 tries.

### What worked
- **i915 flicker fix CONFIRMED**: production grub.cfg (`enable_psr=0 enable_fbc=0
  enable_dc=0`) → no flicker, smooth. This is the boot baseline.
- **eMMC install via PID-1 (init=) — the winning method.** The upstart-triggered
  approaches all FAILED: the tablet's service layer crash-loops (shill/btmanagerd
  SIGABRT on missing modules) + intermittent `i2c_designware` "timeout waiting for
  bus ready", so upstart milestones never settle and the job never fired. Switched
  to `init=/sbin/iconia-init.sh` (runs as PID 1, before upstart). It: mounts
  essentials, does a **udev coldplug** (sdhci-acpi is built-in but its probe defers
  until udev processes uevents — without this /dev/mmcblk0 never appears), runs
  `chromeos-install --dst /dev/mmcblk0 --yes`, re-injects our 0x3f vmlinuz +
  bootia32.efi + grub.cfg (PARTUUID fixed to eMMC ROOT-A) onto the eMMC ESP, and
  powers off. Scripts: `boards/iconia-w4-820/install/{iconia-init,iconia-fixboot,
  iconia-emmc-debug}.sh` + `iconia-install.conf` (obsolete upstart attempt).
- **eMMC install SUCCEEDED**: eMMC ROOT-A PARTUUID=`95DE10DD-E5AA-0C49-8E23-A32012F41F14`,
  eMMC vmlinuz xloadflags=`3f`. (postinst "verity hash verification failed" is
  EXPECTED/harmless — we modified the rootfs and DON'T use ChromeOS verified boot;
  we boot GRUB → vmlinuz → root=PARTUUID ro directly.)
- **"No bootable device" FIXED via the bootmgfw trick.** A fixed eMMC boots only
  via the firmware's persistent NVRAM "Windows Boot Manager" entry
  (→ `\EFI\Microsoft\Boot\bootmgfw.efi`), NOT the removable-media fallback
  (`\EFI\BOOT\BOOTIA32.EFI`) that boots the USB. No efivarfs (CONFIG_EFIVAR_FS
  unset) to add an entry, so we copy our GRUB to that bootmgfw path
  (`iconia-fixboot.sh`, now also folded into `iconia-init.sh`). Firmware then
  loads our GRUB from eMMC → "Booting FydeOS".

### The remaining problem — intermittent eMMC enumeration (KERNEL, not HW)
- Firmware reads the eMMC reliably (loads bootmgfw→GRUB→vmlinuz off it fine, and
  Windows booted it). The flakiness is purely the **Linux eMMC driver**: mmcblk0
  enumerates only ~1/3 of boots; HS200 tuning likely intermittently fails. On eMMC
  boot the kernel then hangs at `rootwait` waiting for mmcblk0p3.
- Root cause = generic+trimmed kernel missing Bay Trail support. Config gaps found:
  `CONFIG_I2C_DESIGNWARE_BAYTRAIL` unset; AXP288 PMIC + REGULATOR_AXP + PMIC_OPREGION
  all absent.
- **STAGED next experiment (ready to deploy): `iconia-emmc-debug.sh`** — re-injects
  the eMMC grub.cfg with `sdhci.debug_quirks2=0x40` (SDHCI_QUIRK2_BROKEN_HS200 →
  disable HS200, force a robuster mode) + a debug console (console=tty1 loglevel=7).
  One boot then either boots reliably (quirk worked) or shows where it hangs.
- **Proper fix if the quirk isn't enough: kernel rebuild** enabling
  CONFIG_I2C_DESIGNWARE_BAYTRAIL + AXP288 PMIC/regulator/OPREGION (relax the trim),
  rebuild kernel+modules, re-inject to eMMC ESP + ROOT-A.

### Deploy recipe (build host crosh; USB moves letters sda<->sdb)
```sh
# find USB (7.45GiB = 15633408 sectors), mount, copy a script, point grub init= at it
U=""; for d in sda sdb sdc; do [ "$(cat /sys/block/$d/size 2>/dev/null)" = 15633408 ] && U=$d; done
sudo mount /dev/${U}3 /tmp/roota; sudo mount -o remount,rw /tmp/roota; sudo mount /dev/${U}12 /tmp/esp
SRC=/media/fuse/crostini_1910d1979a76c12e132e98ff6ca5833087b4d2ce_termina_penguin/source/neilgfoster/iconia/boards/iconia-w4-820/install
sudo cp "$SRC/<script>.sh" /tmp/roota/sbin/<script>.sh; sudo chmod +x /tmp/roota/sbin/<script>.sh
sudo sed -i 's#init=[^ ]*#init=/sbin/<script>.sh#' /tmp/esp/boot/grub/grub.cfg   # or init=/sbin/init for normal
sync; sudo umount /tmp/esp; sudo umount /tmp/roota
# read a PID1 script's trace afterward: mount /dev/${U}3 and cat /iconia-*.log
```
- USB rootfs ro-compat already cleared → `mount -o remount,rw` works. Crostini home
  visible to crosh host at the /media/fuse/... path above (repo lives there).
- PID1 scripts log live to /dev/tty1 (+ /dev/kmsg) AND to a trace file on ROOT-A
  (`/iconia-*.log`) — the ONLY reliable channel (USB-ESP FAT logs / dmesg / stateful
  are lost on the hard power-offs these debug boots need).

## ✅ MILESTONE 8 COMPLETE — eMMC boots standalone to OOBE (2026-07-03)

Full keyboard-free eMMC install achieved. Recap of what made it work:
- **Install**: `iconia-init.sh` as PID 1 (init=) — coldplug udev, chromeos-install,
  re-inject 0x3f kernel + bootia32.efi + grub.cfg (eMMC PARTUUID) + bootmgfw.efi.
- **Bootable**: bootmgfw trick (GRUB at `\EFI\Microsoft\Boot\bootmgfw.efi`).
- **Reliable eMMC**: `sdhci.debug_quirks2=0x40` (HS200 off) in grub, AND for USB
  utility boots, `iconia-emmc-finalize.sh` force-rebinds sdhci-acpi to make the
  eMMC enumerate. KEY GOTCHA: rebinding RENUMBERS mmc hosts (eMMC may become
  mmcblk1), so detect the eMMC by identity (big ~58GiB mmcblk), not fixed mmcblk0.
- **OOBE**: had to re-enable `ui.conf` on eMMC ROOT-A (we'd disabled it on the USB
  rootfs for PID1 console debugging; chromeos-install copied that to eMMC).
- **Prod grub keeps the boot console** (console=tty1 loglevel=7, no keep_bootcon) —
  user wants visible boot activity, not a blank/frozen screen.

eMMC ROOT-A PARTUUID = `95DE10DD-E5AA-0C49-8E23-A32012F41F14`.

## Next actions (session 3)
1. ✅ **eMMC boot reliability CONFIRMED** — ~5/5 cold power-cycles booted to OOBE
   with the HS200-off quirk. (If a boot ever hangs at rootwait, the durable fix is
   the Bay Trail kernel rebuild below.)
2. ✅ **Wi-Fi WORKS** (BCM43241) — depmod + fw decompress + NVRAM (iconia-wifi-fix.sh).
   Remaining HW follow-ups now that module autoload works: audio (fw_sst decompressed
   this pass — re-test), bluetooth, backlight, sensors/auto-rotate. See hardware-status.md.
   Wi-Fi (brcmfmac + firmware/NVRAM), audio (fw_sst_0f28.bin + UCM), backlight,
   auto-rotate/sensors, bluetooth. WiFi is needed to complete OOBE sign-in.
3. **Optional kernel rebuild** enabling `CONFIG_I2C_DESIGNWARE_BAYTRAIL` + AXP288
   PMIC/regulator/OPREGION (relax trim) — would make eMMC/I2C rock-solid and fix
   several HW subsystems at once. Then re-inject kernel+modules to eMMC.
4. **Disable auto-update** on the installed system (would overwrite our eMMC kernel
   with stock 0x2b).


1. Confirm the i915 flicker fix (grub `boots-2026-07-02` release `grub.cfg` /
   `boards/iconia-w4-820/boot/grub.cfg`). If flicker persists, try
   `i915.enable_dpcd_backlight=1` or panel-specific knobs.
2. **Milestone 8 — install to eMMC** (`/dev/mmcblk0` on the tablet, ~58GB):
   - Boot FydeOS from USB, run the FydeOS installer to the eMMC.
   - **BEFORE first eMMC boot** (installer writes the STOCK 0x2b kernel): re-apply our
     fixes to the eMMC — inject `vmlinuz` (0x3f) + `bootia32.efi` + grub.cfg on the eMMC
     ESP (partition 12), clear ro-compat + inject matching modules on eMMC ROOT-A
     (partition 3), and fix `root=PARTUUID=` (changes on eMMC — read with `cgpt`/`blkid`).
   - Same procedure as USB; just target `mmcblk0` instead of the USB disk.
3. Hardware follow-ups (see `boards/iconia-w4-820/hardware-status.md`): audio needs
   firmware (`fw_sst_0f28.bin` failed to load; SST `bytcr_rt5640` + UCM) — use
   `scripts/inject-rootfs.sh`. Check Wi-Fi/BT, backlight, battery.
4. Auto-update will overwrite the eMMC kernel with stock 0x2b → disable auto-update
   on the installed system, or be ready to re-inject.

## Handy commands

```sh
# decisive byte on any kernel image (want low byte with 0x04 set, e.g. 2f/3f):
od -An -tx1 -j $((0x236)) -N 2 vmlinuz.A
# make a ChromeOS rootfs (ext2 with 0xff ro-compat) writable:
dd if=/dev/zero of=<ROOTPART> bs=1 seek=1127 count=1 conv=notrunc   # then mount -t ext4 rw
# rebuild kernel standalone after a config change:
cd ~/openfyde/kernel-6.6 && make olddefconfig && make -j$(nproc) bzImage
# ALWAYS after a kernel config change, rebuild+re-inject modules (modules.builtin!):
make -j$(nproc) modules && make modules_install INSTALL_MOD_PATH=<stage>
```


## ⭐ SESSION 3 WRAP (2026-07-03)

Kernel rebuilt with Bay Trail HW enablement (`baytrail-hw.config`) → 6.6.76 #6,
xloadflags still 0x3f, re-injected to eMMC (`iconia-kernel-reinject.sh`).

**Working now:** eMMC standalone boot (first-try since the rebuild — i2c semaphore
likely fixed enumeration; HS200 quirk still in grub, try dropping it), **Wi-Fi**
(now native `.xz` firmware via `FW_LOADER_COMPRESS_XZ`), touchscreen, display.

**Still broken / follow-ups (all polish; device is usable):**
- **Backlight** ❌ HARD — `/sys/class/backlight` empty even with PWM_CRC; i915
  `[DSI-1] Failed to get the PMIC PWM chip`; Crystal Cove PMIC does NOT bind →
  board uses a different backlight PWM path. Needs investigation (AXP288 / LPSS
  PWM / panel-native). Screen usable at full brightness.
- **Audio** ❌ — SST vs SOF contend, no firmware/topology/UCM.
- **Auto-rotate/sensors** ❌ — accel didn't come up (SMO91D0 hub / i2c).
- **Bluetooth** 🟡 — stack loads, no hci0 (UART controller not bound).

**Utility-boot pattern (all the `iconia-*.sh` in `install/`):** deploy script to
USB `/sbin`, point grub `init=` at it, PID1 does the work, logs to ROOT-A trace +
/dev/tty1, powers off. eMMC reached via sdhci-acpi rebind + identity detect
(rebind RENUMBERS mmc → find big mmcblk). **USB ROOT-A is ~100% full & re-enumerates
sda<->sdb** — mount fresh each time; free space by removing decompressed fw dupes.

## ✅ BACKLIGHT FIXED (session 4, 2026-07-03)

**Brightness slider works.** Root cause was a two-part kernel gap, found via
`iconia-backlight-diag.sh` (raw-PWM dim test confirmed the HW path):
1. `# CONFIG_GPIO_CRYSTAL_COVE is not set` — the `gpio_crystalcove` GPIO chip
   i915's DSI/VBT panel code needs to "own" the panel never registered. Fixed:
   `CONFIG_GPIO_CRYSTAL_COVE=y` (in `baytrail-hw.config`). PWM_CRC/INTEL_SOC_PMIC
   were already on — that's why raw `pwmchip0` (crystal_cove_pwm) dimmed the panel.
2. **Probe-ordering race**: even with the GPIO chip enabled, built-in i915 probes
   (~17.7s) BEFORE the Crystal Cove MFD/GPIO (on the async i2c-designware bus)
   registers `gpio_crystalcove` (~18.1s) → i915 logs "cannot find GPIO chip
   gpio_crystalcove, deferring" → "Failed to own gpio for panel control" → "Failed
   to get the PMIC PWM chip" and never retries. Fix: **`CONFIG_DRM_I915=m`** — i915
   loads from userspace AFTER the PMIC/GPIO are up. (This is also how ChromeOS ships
   i915 natively; building it in was our deviation.) Kernel = **6.6.76 #8**,
   xloadflags still 0x3f.

**Space gotcha (important for any future reinject):** i915-as-a-module grew the
module tar 153M→**201M**, which OVERRAN eMMC ROOT-A (only ~159M free). `iconia-
kernel-reinject.sh` now reclaims space before extract: (a) drop decompressed
firmware that has an `.xz` sibling, (b) `rm -rf` firmware for hardware this tablet
lacks (amdgpu/radeon/nvidia/iwlwifi/ath*/rtw*/mediatek/qcom/… — KEEP i915, brcm,
intel audio, regulatory.db). A FAILED reinject leaves a partial module tree (rm ran
+ extract died) → device bootloops (last console line "bootconsole disabled"); the
cure is simply a successful reinject.

## 🟡 AUTO-ROTATE: kernel DONE, blocked on FydeOS userspace (session 4, 2026-07-03)

The accelerometer is an **STMicro HID-over-I2C sensor hub** (ACPI `SMO91D0`, _CID
`PNP0C50`, VID:PID `0483:91D1`), NOT a raw IIO accel — its report descriptor is a
standard HID sensor (usage page `05 20`, accel collection `09 73`). Enabled the HID
sensor stack (`HID_SENSOR_HUB` + `HID_SENSOR_ACCEL_3D`/gyro/magn/incl/rotation/als,
all `=m`) in `baytrail-hw.config` → kernel **6.6.76 #9**. **Verified on the eMMC**
(via `iconia-emmc-sensor-check.sh` — LoadPin blocks side-loading modules from a
non-booted rootfs, so the test must run on the eMMC): `hid-sensor-hub` binds
SMO91D0 and all six iio devices appear incl. `iio:device3 name=accel_3d` and
`dev_rotation`. **So the kernel side is complete; remaining no-rotate is FydeOS
userspace** (iioservice/mems_setup: the HID accel likely lacks a `location=lid`
tag / mount-matrix wiring Chrome needs). Kernel diag artifacts:
`install/iconia-sensor-diag.sh`, `iconia-sensor-load.sh` (LoadPin-blocked),
`iconia-emmc-sensor-check.sh`.

**Force-load experiment RULED OUT module-timing (2026-07-03):** `iconia-sensor-
boot.sh` (PID1 pre-init that modprobes the whole HID-sensor stack, then
`exec /sbin/init`) armed via `iconia-emmc-armsensor.sh`. Booted to OOBE with
accel_3d loaded before init → **still no rotation**. So it is NOT a load/timing
issue; it is FydeOS iioservice/Chrome not adopting the HID accel as the lid
rotation sensor. Next attempt (needs dev-mode/crosh shell): inspect
`/run/iioservice`, `mems_setup`, udev `*iioservice*` rules; likely need to tag the
accel with `location`/`label=accel-display` + an identity mount-matrix so
iioservice exposes it to Chrome. The `armsensor` toggle can DISARM (restore
init=/sbin/init) by re-running it.

## ✅ AUDIO FIXED (session 4, 2026-07-03) — speaker works, survives reboot

Codec = **Realtek RT5640** (i2c `10EC5640`); DSP = **legacy SST atom** (card 0
`bytcr-rt5640`, config `stereo-spk-dmic1-mic`; SOF also present but SST won). Two
parts:
1. **Kernel**: trim.config had dropped `SND_SOC_RT5640` + `SND_SOC_INTEL_BYTCR_RT5640_MACH`
   → no card. Enabled both → kernel **6.6.76 #10** (in `baytrail-hw.config`).
2. **UCM (the real blocker)**: FydeOS ships UCM only for `sof-hda-dsp`, nothing for
   our card, so CRAS couldn't route it (raw `aplay hw:0,0` failed hw_params = DPCM
   FE had no connected BE). Fix: a **self-contained `bytcr-rt5640` UCM** built from
   alsa-ucm-conf's verified sequences (bytcr PlatformEnableSeq DSP pipe +
   rt5640 EnableSeq codec routing in SectionVerb; Speaker enable in the device;
   volume mapped to `Speaker Playback Volume`/`DAC1`). Proven live: manual amixer
   sequence → white noise → YouTube; then installed UCM → **sound survives cold
   reboot**. On-screen volume works.

Repo artifacts: `boards/iconia-w4-820/audio/{HiFi.conf,bytcr-rt5640.conf}` +
`install/iconia-ucm-install.sh` (remounts rootfs rw, drops UCM into
`/usr/share/alsa/ucm2/conf.d/bytcr-rt5640/`, symlinks `bytcrrt5640`, restarts cras).
NOTE: UCM was installed to the live eMMC rootfs at runtime — bake it into the rootfs
image for a clean reproducible build. Diag: `install/iconia-audio-diag.sh`.

### 🔑 SSH LIVE-DEBUG WORKS (session 4) — huge workflow unlock
Root shell on tablet over wifi ended the multi-boot loop. What finally worked:
FydeOS `sshd_config` wants host keys at `/mnt/stateful_partition/etc/ssh/` (copied
ours there); then run sshd manually (NOT persistent yet). Connect from the **crosh
host** (Crostini can't reach LAN): `ssh -i /tmp/ik root@192.168.1.31` (key =
build-host `~/.ssh/iconia_ed25519`, copied to crosh `/tmp/ik`). Push local scripts:
`ssh ... 'sh -s' < /media/fuse/<crostini>/<file>`. `stop powerd` first (suspend/
resume broken — screen won't wake). TODO: make sshd auto-start at boot (privsep
preauth-255 with our own invocation is unsolved; manual start works).

## 🔧 SSH-for-live-debug (in progress, session 4) — the current focus

Goal: a root shell on the tablet to iterate audio/sensors without the multi-boot
PID1 loop (OTG keyboard now works; dev mode + `cros_debug` enabled; crosh `shell`
works; tablet IP **192.168.1.31**). Facts established:
- Our debug SSH key: build host `~/.ssh/iconia_ed25519` (pub in tablet
  `/root/.ssh/authorized_keys`). Crostini CANNOT reach the LAN (NAT) — ssh must run
  from the crosh host (on LAN) or a local agent.
- FydeOS `sshd_config` expects host keys at **`/mnt/stateful_partition/etc/ssh/`**
  (not /etc/ssh). Copied ours there.
- Inbound is firewalled: `iptables -I INPUT -p tcp --dport 22 -j ACCEPT` (resets each
  boot). Suspend/resume is broken (screen won't wake) → run `stop powerd` while
  debugging.
- **BLOCKER**: manual `sshd -o UsePAM=no -o PermitRootLogin=prohibit-password -o
  AuthorizedKeysFile=/root/.ssh/authorized_keys` LISTENS and accepts the connection,
  but the **preauth privsep child exits 255 right after `permanently_set_uid`** (no
  `fatal:` line; no seccomp dmesg because `audit=0`). Kernel HAS SECCOMP+FILTER.
- `fydeos-sshd-server` job = reverse tunnel for cloud "remote-help", NOT a local
  listener (dead end). **UNTRIED: `start openssh-server`** (the other job in
  /etc/init) — may be a normal local sshd that just works; try this FIRST.
- Also install an x86_64 static node for a LOCAL agent: ChromeOS base has **no
  libstdc++**, so official node fails; use a self-contained build or ship libstdc++.
  `/usr/local` is writable+exec in dev mode.
- Repo: `install/iconia-emmc-sshsetup.sh` installs sshd via upstart + adds
  `cros_debug` to eMMC grub. Prod grub.cfg now carries `cros_debug` [[iconia-final-build-cros-debug]].

## 🟠 AUTO-ROTATE (session 4, 2026-07-03) — kernel/sensor DONE, blocked in iioservice

Chased end-to-end over the live SSH shell. What WORKS now:
- Tablet mode forced via `/etc/chrome_dev.conf` (`--enable-tablet-form-factor`
  `--force-tablet-mode=touch_view`). ChromeOS UI is in tablet mode.
- HID accel driver patched (`patches/hid-accel-rotation.patch`, applied to
  `~/openfyde/kernel-6.6/drivers/iio/accel/hid-sensor-accel-3d.c`): exposes
  `label=accel-display`, `in_accel_location=lid` (ext_info SHARED_BY_TYPE), and
  `in_accel_mount_matrix` (identity). iioservice now reads all of these (its
  location/label/mount_matrix errors are gone for accel_3d).
- **Chrome ADOPTS the accel**: chrome log shows `Enter tablet mode` + ash
  `accel_gyro_samples_observer` actively polling the accel device.
- **Sensor streams**: reading `/dev/iio:deviceN` directly (buffer enabled, freq=10,
  record=24B: 3×s32 + s64 ts) yields live changing X/Y/Z at ~10Hz.

THE WALL: ash logs `Device N: A read timed out` repeatedly — **iioservice's
buffered read of the accel times out even though the raw buffer streams when we
read it directly**. freq is correctly 10, buffer/buffer0 enabled. The one thing
iioservice still can't read is `in_accel_sampling_frequency_available` (ENOENT).
Likely a closed iioservice ↔ iio buffer-fd interaction; skeptical the missing
`_available` is the cause since the rate is already set and the buffer streams.
=> Kernel/sensor side is COMPLETE; remaining work is in closed ChromeOS userspace
(iioservice/ash) or a subtle iio buffer-fd path. Reasonable to PARK here.

**Vermagic gotcha for module-only rebuilds** (learned here): editing a kernel
source file makes the tree dirty → module vermagic gets `-dirty` and won't load on
the deployed #10 kernel (`6.6.76-gabcfb16364e1`). Fix: patched
`scripts/setlocalversion` to call `scm_version --no-dirty` (in the patch). Then a
single `.ko` can be rebuilt + hot-pushed over SSH:
`ssh root@IP 'mount -o remount,rw /; cat > /lib/modules/<ver>/kernel/.../x.ko.gz; mount -o remount,ro /' < x.ko.gz` then reboot.

## ✅ DEFAULT PORTRAIT + TABLET MODE (session 4, 2026-07-04)

Device boots to **tablet mode, portrait, right-side-up**, persistent, with manual
rotation (Ctrl+Shift+Refresh). Auto-rotate still parked. Full how-to +
reproducible artifacts: `boards/iconia-w4-820/display/`. Summary:
- Kernel **DRM panel-orientation quirk** (`lcd800x1280_leftside_up`) for
  `Iconia W4-820P` → desktop defaults to right-side-up portrait persistently
  (ChromeOS wouldn't persist a manual rotation; no stable EDID). In
  `patches/hid-accel-rotation.patch`; bzImage rebuild, vermagic unchanged.
- **cros_config form-factor=CHROMESLATE** (`display/configfs-chromeslate.img`).
- `/etc/chrome_dev.conf`: `--force-tablet-mode=touch_view` (tablet mode).
- **Boot splash** pre-rotated +90° (`display/boot-splash-portrait.tar`) — frecon
  has no rotate flag and interprets orientation opposite to Chrome.

## ⭐ SESSION 4 WRAP (2026-07-04) — big session

Delivered (all live-debugged over the new SSH channel — the key unlock):
- ✅ **Backlight** — `GPIO_CRYSTAL_COVE=y` + `DRM_I915=m` (probe-order race).
- ✅ **Audio** — RT5640 + bytcr_rt5640 machine driver + self-contained
  `bytcr-rt5640` UCM (`audio/`); survives reboot; on-screen volume works.
- ✅ **SSH live-debug** — root shell over wifi; ended the multi-boot loop.
  Persistent across reboot. Connect from crosh host: `ssh -i /tmp/ik root@<ip>`.
- ✅ **Default portrait + tablet mode** (this section).
- 🟠 **Auto-rotate** — sensor/kernel/metadata all perfect; Chrome reads samples
  (timeouts=0); blocked in closed ash rotation state machine. Parked.

Kernel is now **6.6.76-gabcfb16364e1** (stable vermagic via `--no-dirty`), built
from `~/openfyde/kernel-6.6` with `baytrail-hw.config` + the patch. Single-module
hot-rebuild+SSH-push workflow proven (see PROGRESS above / display/README.md).

## Next actions (session 5)

**State: device is a genuinely usable FydeOS tablet — boots eMMC standalone;
wifi, touch, display, brightness, AUDIO, tablet-mode + portrait all work.**

1. **Bake everything into a reproducible image build** (currently many fixes are
   hot-applied to the live eMMC over SSH). Fold into the rootfs/kernel build:
   the kernel patch, `baytrail-hw.config`, the UCM, cros_config CHROMESLATE,
   chrome_dev.conf flag, rotated splash, sshd autostart.
2. **Disable auto-update** (would overwrite our 0x3f/patched kernel with stock 0x2b).
3. Remaining HW polish (optional): **bluetooth** (no hci0; hci_uart/serdev bind +
   BCM .hcd), **hardware volume/buttons**, **drop HS200 quirk** (`sdhci.debug_quirks2=0x40`).
4. **Auto-rotate** revisit only with iioservice debug logging or a Chrome/ash
   angle — it's the closed layer; low ROI.

## ✅ SESSION 5 (2026-07-04) — hardware buttons + OSK + long-press crosh

Three things landed, all live-debugged over SSH.

### ✅ Hardware buttons (power / volume ± / Windows-home)
- Root cause: `trim.config` had `# CONFIG_INPUT_SOC_BUTTON_ARRAY is not set`, so the
  ACPI "Windows button array" (PNP0C40) had no driver → no button input at all.
- Fix in `config/baytrail-hw.config`: `CONFIG_INPUT_SOC_BUTTON_ARRAY=m` (+
  `CONFIG_INTEL_INT0002_VGPIO=y` for power-button wake-from-S0ix; the vGPIO part
  is built-in, so it only takes effect after a full bzImage reinject — the buttons
  themselves work from the module alone).
- Deployed as a single hot-pushed module (no reflash): `soc_button_array.ko`
  (vermagic `6.6.76-gabcfb16364e1`, clean) → `/lib/modules/.../kernel/drivers/input/misc/`
  + `depmod`. LoadPin blocks `insmod` from `/tmp`; must live on the pinned rootfs then
  `modprobe`. The driver names its input nodes **`gpio-keys`** (two of them), NOT
  "soc_button_array" — match buttons by capability (KEY_LEFTMETA=125), not name.
- Power + volume are auto-adopted by ChromeOS; the Windows/home button = `KEY_LEFTMETA`
  → launcher/home.

### ✅ On-screen keyboard (OSK) fix
- OSK had silently stopped appearing (pre-existing, unrelated to buttons — confirmed
  by unloading soc_button_array, no change). In tablet mode ChromeOS auto-hides the
  OSK unless it's forced. Fix: append **`--enable-virtual-keyboard`** to
  `/etc/chrome_dev.conf` (persistent on rootfs) + `restart ui`. OSK back.
- BONUS: because this flag *forces* the OSK on, a virtual-keyboard input device no
  longer suppresses it — which is what makes the crosh daemon below safe (an early
  attempt with a persistent uinput keyboard had disabled the auto-OSK).

### ✅ Long-press Windows button → crosh (keyboard-free crosh access)
- Motivation: on a keyboard-less tablet, opening crosh is otherwise impossible
  (VT2 needs a physical keyboard; browser crosh can use the OSK). `Ctrl+Alt+T` opens
  browser crosh.
- `install/iconia-buttond.c` (static x86_64, in `/usr/local/sbin/iconia-buttond`,
  autostarted by `install/iconia-buttond.conf` upstart job `start on started ui`):
  watches the button evdev node (matched by KEY_LEFTMETA capability), and on a
  **≥2 s hold then RELEASE** injects `Ctrl+Alt+T` via `/dev/uinput`.
- TWO hard-won gotchas (both cost several iterations):
  1. **Must fire on RELEASE, not while held.** The Windows button *is* KEY_LEFTMETA
     (the Meta modifier). Injecting Ctrl+Alt+T while it's physically down makes Chrome
     see Meta+Ctrl+Alt+T ≠ the crosh accelerator. Waiting for release gives a clean
     Ctrl+Alt+T. (A fire-while-held build fired correctly per its debug log but never
     opened crosh — this is why.)
  2. **uinput device must be `BUS_USB` with a vendor/product id**, not `BUS_VIRTUAL` —
     ChromeOS/ozone routes accelerator keys from a USB-bus keyboard but ignored a
     virtual-bus one.
- Hold threshold = `HOLD_MS` (currently **2000 ms**); one-line change + rebuild to tune.
- `uinput` is a module (`CONFIG_INPUT_UINPUT=m`); persisted to the rootfs + `depmod`,
  the upstart job `modprobe`s it in pre-start.
- Diag tools kept: `install/iconia-btnmon.c` (dumps every key event across all evdev
  nodes — proved the button is code 125 on `gpio-keys` with no autorepeat) and
  `install/iconia-injtest.c` (one-shot Ctrl+Alt+T injector — proved injection opens
  crosh, isolating the daemon logic from the injection path).

### Install scripts
- `install/iconia-buttons-install.sh` — installs soc_button_array.ko + depmod.
- `install/iconia-buttond-install.sh` — installs the daemon binary + uinput.ko +
  upstart job. (Both hot-apply to the live eMMC over SSH; still need baking into the
  reproducible image — see next actions #1.)

### Still TODO (unchanged priorities)
- **Bake into the reproducible build**: soc_button_array in-config is done, but the
  daemon binary/upstart job/uinput persistence + the `--enable-virtual-keyboard`
  chrome_dev.conf flag are hot-applied to the live eMMC — fold into the rootfs image.
- Disable auto-update (would overwrite the patched kernel).

### Artifact cache scaffolded (backbone of the prepare-USB flow)
- `boards/<id>/artifacts.manifest` + `scripts/resolve-artifacts.sh` (cache lookup:
  fingerprint config/patches/sources → tag → GitHub Release; download+verify) +
  `scripts/publish-artifacts.sh` (cache fill). Design: `docs/artifact-cache.md`.
  Heavy artifacts (kernel/modules ~210MB) go in Releases, NOT git/git-lfs.
- Dry-run verified (correct cache-miss + build instructions). NOT yet published —
  see the wrap note below.

## 🚧 SESSION 5 WRAP — device NOT finished; do not finalize yet (2026-07-04)

Device is a very usable FydeOS tablet, but configuration is **incomplete**. Do NOT
publish the artifact-cache bundle or bake the final rootfs image until the backlog
below is done — the fingerprint tag is meant to keep changing as fixes land.

**Remaining configuration backlog (next session, pick one — user wants to continue):**
1. **Bluetooth** 🟡 — stack loads, no `hci0`; bind the UART/serdev BT controller +
   load BCM `.hcd` firmware. Self-contained, live-debuggable over SSH.
2. **Memory optimization** — 2 GB device; zram/swap, ChromeOS mem knobs, trim
   services. Biggest impact on everyday feel.
3. **Power optimization** — suspend/S0ix broken (screen won't wake), battery/charging
   via AXP288 (stack already enabled). Partly firmware-limited on Bay Trail → modest
   ceiling, more investigation.
4. **Drop HS200 quirk** (`sdhci.debug_quirks2=0x40`) — quick: test over cold boots.
5. Lower priority: microSD, cameras (untested); auto-rotate (parked, closed iioservice).

Also on deck (deferred to end): bake fixes into image, disable auto-update, publish
cache bundle. Repo state committed on branch `session-5-buttons-osk-crosh`.

--- (older session-4 target list retained below) ---

**State: BACKLIGHT DONE; AUDIO DONE (UCM);
AUTO-ROTATE kernel-ready (accel_3d enumerates) but not rotating (FydeOS userspace).
Tablet boots FydeOS from eMMC standalone; wifi/touch/display/brightness work.
Kernel now 6.6.76 #10 (i915=m + HID sensors + RT5640). Actively standing up SSH/
local-agent for live debugging.**

Build artifacts on the Crostini build host (NOT in git): `~/openfyde/kernel-6.6/`
(.config = #8, i915=m), `~/openfyde/modules-baytrail.tar` (201M, i915=m set),
`boards/iconia-w4-820/out/vmlinuz` (#8). Reinject via `iconia-kernel-reinject.sh`
(tar→USB p1, vmlinuz→USB ESP p12; depmod runs on-device).

Build artifacts on the Crostini build host (NOT in git):
- `~/openfyde/kernel-6.6/` — tree; `.config` = Bay Trail build #6. Rebuild:
  `cd ~/openfyde/kernel-6.6 && make -j8 bzImage modules` (keep xloadflags 0x3f).
  bzImage == `boards/iconia-w4-820/out/vmlinuz` (sha 6b72156f).
- `~/openfyde/modules-baytrail.tar` (153M) — injected module set.
- Re-inject a new build via `iconia-kernel-reinject.sh` (stage tar→USB p1,
  vmlinuz→USB ESP). depmod runs ON-DEVICE (build-host depmod can't read .ko.gz).

Pick a target:
1. ✅ **Backlight — DONE** (see section above: GPIO_CRYSTAL_COVE=y + DRM_I915=m).
2. **Audio** — rootfs uses `snd_sof`; likely need `intel/sof/sof-byt*.ri` +
   `intel/sof-tplg/*.tplg` + ALSA UCM; blacklist legacy `intel_sst` so they don't
   contend (or vice versa). Firmware loads from .xz natively now.
3. **Drop HS200 quirk?** eMMC booted first-try on Bay Trail kernel — try removing
   `sdhci.debug_quirks2=0x40` from eMMC grub over several cold boots.
4. **Bluetooth** — no hci0; needs `hci_uart`/serdev bind + `BCM-0bb4-0306.hcd`.
5. **Sensors/auto-rotate** — accel (`SMO91D0`/`kxcjk`) didn't enumerate.

Utility-boot how-to: deploy `install/iconia-*.sh` to USB `/sbin`, `sed` grub
`init=` to it, boot USB, read ROOT-A trace. USB ROOT-A ~full & re-enumerates
sda<->sdb — mount FRESH each command; free space by deleting decompressed
`/lib/firmware/**` dupes (kernel loads .xz natively now). eMMC PARTUUID
95DE10DD-E5AA-0C49-8E23-A32012F41F14.
