#!/bin/sh
# Iconia W4-820 — pre-init sensor loader (PID 1) for the eMMC. At normal boot the
# built-in hid-generic grabs the SMO91D0 HID sensor hub first; if hid-sensor-hub
# doesn't autoload (group/modalias race) the accel never enumerates and FydeOS
# iioservice never sees it -> no auto-rotate. This runs as init=, force-loads the
# HID-sensor stack from the booted rootfs (LoadPin-approved), then execs the real
# /sbin/init so the device boots normally to OOBE with accel_3d already up.
# If rotation then works, the cure is just loading these modules at boot.
export PATH=/usr/sbin:/usr/bin:/sbin:/bin

# Mount just enough for modprobe, then unmount so upstart starts from a clean slate.
mount -t proc proc /proc 2>/dev/null
mount -t sysfs sys /sys 2>/dev/null

for m in hid-sensor-hub hid-sensor-iio-common hid-sensor-trigger \
         hid-sensor-accel-3d hid-sensor-incl-3d hid-sensor-rotation \
         hid-sensor-gyro-3d hid-sensor-magn-3d hid-sensor-als; do
  modprobe "$m" 2>/dev/null
done

# hid-sensor-hub reclaims the device from hid-generic on load; give it a moment.
sleep 2

umount /sys 2>/dev/null
umount /proc 2>/dev/null

exec /sbin/init "$@"
