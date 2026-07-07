#!/bin/sh
# iconia-accel-rotation-install.sh — enable correct screen AUTO-ROTATION on the
# LIVE eMMC system over SSH. Run from the crosh host (Crostini can't reach LAN):
#   push the module next to it first, then:
#     ssh -i /tmp/ik root@192.168.1.31 'sh -s' < iconia-accel-rotation-install.sh
# Expects /tmp/hid-sensor-accel-3d.ko.gz already on the tablet.
#
# WHAT THIS FIXES (session 12, 2026-07-07):
#   The SMO91D0 HID accelerometer sat 90 deg out from the panel with an identity
#   mount matrix, and ChromeOS ash never treated it as the display sensor, so
#   auto-rotate was 90 deg wrong / disabled. This patched hid-sensor-accel-3d.ko
#   (out/hid-sensor-accel-3d.ko.gz, from patches/hid-accel-rotation.patch):
#     * hardcodes the mount matrix "0,-1,0; 1,0,0; 0,0,1" (90 deg about Z) directly
#       in the driver — the earlier SSDT _DSD approach put "mount-matrix" on the
#       ACPI I2C-HID node, which the child MFD platform device never inherits, so
#       iio_read_mount_matrix() silently fell back to identity. Hardcoding always
#       applies. (Sign confirmed correct on-device: all 4 orientations upright.)
#     * sets label="accel-display" + location="lid" + a samp_freq list so
#       ChromeOS iioservice/ash consumes it for rotation like a cros-ec accel.
#
#   The userspace udev route (61-iconia-accel.hwdb / ACCEL_MOUNT_MATRIX) does NOT
#   work here: ChromeOS iioservice reads the kernel sysfs in_accel_mount_matrix
#   (read-only), not the freedesktop udev prop, and there is no ACPI configfs for a
#   runtime SSDT. So this MUST be the kernel module.
#
# vermagic 6.6.76-gabcfb16364e1 matches the deployed kernel (setlocalversion
# --no-dirty), so the module hot-loads with NO new vmlinuz. It IS in use at
# runtime, so we overwrite in the tree + depmod + REBOOT (can't rmmod live).
#
# NOTE: auto-rotate only runs in TABLET mode. The device boots to laptop and you
# toggle to tablet via the FydeOS switch (see iconia-desktop-mode-install.sh).
set -e
KVER=$(uname -r)
MODDIR="/lib/modules/$KVER/kernel/drivers/iio/accel"
GZ=/tmp/hid-sensor-accel-3d.ko.gz
DST="$MODDIR/hid-sensor-accel-3d.ko.gz"
WANT_SHA=fa13192fc236edad77fc1d22afa5a54c36622898b38875eb2483776c60aa5786

[ -f "$GZ" ] || { echo "ERROR: $GZ not found — push it to the tablet first"; exit 1; }
GOT_SHA=$(sha256sum "$GZ" | awk '{print $1}')
[ "$GOT_SHA" = "$WANT_SHA" ] || { echo "ERROR: sha mismatch ($GOT_SHA != $WANT_SHA)"; exit 1; }

echo "== persist patched accel module into rootfs =="
mount -o remount,rw /
[ -f "$DST" ] && cp "$DST" "$DST.bak.$(date +%s)"
cp "$GZ" "$DST"
echo "tablet module sha: $(sha256sum "$DST" | awk '{print $1}')"
depmod "$KVER"
sync
mount -o remount,ro / || true

echo
echo "== rebooting so the new module loads at hci... accel bring-up =="
echo "After reboot verify:"
echo "  cat /sys/bus/iio/devices/iio:device5/in_accel_mount_matrix  # want 0,-1,0; 1,0,0; 0,0,1"
echo "  cat /sys/bus/iio/devices/iio:device5/label                  # want accel-display"
echo "Then toggle to tablet mode and rotate — desktop should stay upright."
reboot
