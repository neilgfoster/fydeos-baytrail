# Iconia W4-820 — display orientation + auto-rotate (session 12, 2026-07-07)

**Auto-rotate WORKS** as of session 12. The device is a convertible
(cros_config form-factor=CHROMESLATE, is-lid-convertible=true): it boots to
**laptop** mode and you switch to **tablet** via the FydeOS toggle (Local State
`show_switch_tablet_laptop_button`). In tablet mode the screen auto-rotates and
stays upright in all four orientations. Laptop mode is kept for external-monitor
use. There is NO FydeOS pref for "tablet-by-default while keeping the toggle"
(forcing tablet = tablet-only, kills the toggle), so laptop-default is accepted.

The auto-rotate fix is the patched **hid-sensor-accel-3d.ko** module (see
`install/iconia-accel-rotation-install.sh` + `patches/hid-accel-rotation.patch`):
it hardcodes the accel mount matrix `0,-1,0; 1,0,0; 0,0,1` and tags the sensor
`label=accel-display`/`location=lid` so ChromeOS ash uses it. This is a MODULE
(vermagic-matched, hot-loads, no vmlinuz needed). The userspace udev/hwdb route
does NOT work — ChromeOS iioservice reads the read-only kernel sysfs mount matrix,
not the freedesktop `ACCEL_MOUNT_MATRIX` udev prop, and there's no ACPI configfs.

Panel is **portrait-native 800x1280** DSI. ChromeOS defaults it to landscape, so
the *base/boot* orientation is still 90° out unless the DRM panel_orientation
quirk (item 1 below, needs a vmlinuz rebuild) is applied — currently worked around
with a manual Settings → Displays → Orientation = 90° in laptop mode. The DRM
quirk is the only remaining OPTIONAL piece (correct boot splash + base orientation
without the manual 90°); auto-rotate itself no longer depends on it.

## What's applied on the device (make reproducible in the image)

1. **Kernel DRM panel-orientation quirk** — `patches/hid-accel-rotation.patch`
   adds an Acer `Iconia W4-820P` entry to `drm_panel_orientation_quirks.c` using
   `lcd800x1280_leftside_up` (LEFT_UP). This makes the desktop default to
   right-side-up portrait, persistently, at login + session. (RIGHT_UP = upside
   down; the two 800x1280 helpers are the only 90° options.) Built into vmlinuz
   (`CONFIG_DRM=y`), so it needs a bzImage rebuild — but vermagic is unchanged
   (`--no-dirty` setlocalversion fix in the same patch), so modules are NOT
   re-injected; only `out/vmlinuz` is pushed to the eMMC ESP `/syslinux/vmlinuz.A`.

2. **cros_config form-factor = CHROMESLATE** — `display/configfs-chromeslate.img`
   (repacked `/usr/share/chromeos-config/configfs.img` with
   `v1/chromeos/configs/0/hardware-properties/{form-factor=CHROMESLATE,
   has-lid-accelerometer=true,is-lid-convertible=true}`). Marks it a tablet.
   Install: `mv` over `/usr/share/chromeos-config/configfs.img`, reboot.

3. **UI mode flag** — `/etc/chrome_dev.conf` (needs cros_debug).
   ~~`--force-tablet-mode=touch_view`~~ (s5, force tablet) →
   ~~`--force-tablet-mode=clamshell`~~ (s10, force desktop). **Superseded session
   12:** NO force flag — mode is driven by the FydeOS Laptop/Tablet toggle
   (laptop default; tablet auto-rotates). OSK stays via `--enable-virtual-keyboard`.
   Install: `install/iconia-desktop-mode-install.sh` (now removes the force flag).
   Also required: the patched accel module — `install/iconia-accel-rotation-install.sh`.

4. **Boot splash rotated 90° CW** — `display/boot-splash-portrait.tar` holds the
   120 `boot_splash_frame*.png` (100% + 200%) rotated +90° so `frecon` draws them
   upright (frecon has no rotate flag and interprets panel orientation opposite to
   Chrome, so the images themselves are pre-rotated). Install: extract over
   `/usr/share/chromeos-assets/` (remount rootfs rw), reboot. Regenerate from stock:
   `mogrify -rotate 90 boot_splash_frame*.png`.

## Live-debug push recipe (over SSH, no USB)
```
# vmlinuz -> eMMC ESP:
ssh root@<ip> 'D=$(rootdev -s -d); mount ${D}p12 /tmp/esp; cat > /tmp/esp/syslinux/vmlinuz.A; umount /tmp/esp' < out/vmlinuz
# rootfs files (splash, configfs, ucm, chrome_dev.conf): mount -o remount,rw / ; write ; reboot
```
