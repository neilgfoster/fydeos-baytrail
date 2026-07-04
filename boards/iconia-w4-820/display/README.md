# Iconia W4-820 — tablet mode + default portrait (session 4, 2026-07-04)

The device now boots to **tablet mode, portrait, right-side-up** by default, with
**manual rotation** available (Ctrl+Shift+Refresh / Settings → Displays → Orientation).
Auto-rotate is NOT working (parked — blocked in closed ash; see PROGRESS).

Panel is **portrait-native 800x1280** DSI. ChromeOS otherwise defaults it to
landscape and doesn't persist a manual rotation (no stable EDID/display-id).

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

3. **Tablet mode flag** — append to `/etc/chrome_dev.conf` (needs cros_debug):
   `--force-tablet-mode=touch_view`  (forces tablet UI; CHROMESLATE alone did not
   enter tablet mode with a single accel).

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
