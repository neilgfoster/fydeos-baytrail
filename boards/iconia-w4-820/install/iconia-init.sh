#!/bin/sh
# Iconia W4-820 — eMMC auto-install as PID 1 (init= wrapper).  KEYBOARD-FREE.
#
# Booted via grub `init=/sbin/iconia-init.sh`. Runs BEFORE upstart, so it dodges
# the service crash-storm (shill/btmanagerd abort-loop on missing modules) and
# never depends on an upstart milestone firing. chromeos-install needs only
# block devices (DEVTMPFS_MOUNT=y populates /dev) and tolerates `udevadm settle`
# timing out, so this minimal environment is enough.
#
# Flow: mount essentials -> install FydeOS to eMMC -> re-inject our 0x3f kernel +
# bootia32.efi + grub.cfg (fixed PARTUUID) onto the eMMC ESP -> power off.
# All output goes LIVE to /dev/tty1 (+ /dev/kmsg + a ROOT-A trace file).
#
# As PID 1 we must NEVER exit without powering off (kernel would panic), so the
# script always ends in poweroff.
export PATH=/usr/sbin:/usr/bin:/sbin:/bin

CON=/dev/tty1
TARGET=/dev/mmcblk0
UESP_MNT=/mnt/iconia-uesp
EESP_MNT=/mnt/iconia-eesp
TRACE=/iconia-trace.log

# --- minimal early mounts (DEVTMPFS_MOUNT=y already gave us /dev) ---
mount -t proc     proc /proc 2>/dev/null
mount -t sysfs    sys  /sys  2>/dev/null
mount -t devtmpfs dev  /dev  2>/dev/null   # harmless no-op if already mounted
mount -t tmpfs    tmp  /tmp  2>/dev/null
mount -t tmpfs    run  /run  2>/dev/null
mount -o remount,rw / 2>/dev/null || true  # so the trace file persists

say() {
  _m="[$(date -u '+%H:%M:%S' 2>/dev/null)] $*"
  echo "ICONIA $_m" > "$CON"    2>/dev/null || true
  echo "$_m"       >> "$TRACE"  2>/dev/null || true
  echo "ICONIA: $*" > /dev/kmsg 2>/dev/null || true
  sync 2>/dev/null || true
}

finish() {   # never return; always power the machine off
  say "$1"
  say "powering off in ${2:-10}s ..."
  sync; sleep "${2:-10}"
  poweroff -f 2>/dev/null
  echo o > /proc/sysrq-trigger 2>/dev/null
  # last resort: spin so PID1 never exits
  while true; do sleep 60; done
}

n=0; while [ "$n" -lt 6 ]; do echo "" > "$CON"; echo "########## ICONIA PID1 INSTALLER ##########" > "$CON"; n=$((n+1)); done
say "=== iconia-init.sh running as PID $$ ==="

partdev() { case "$1" in *[0-9]) echo "$1p$2" ;; *) echo "$1$2" ;; esac; }

# --- coldplug: bring hardware up like a normal boot, but WITHOUT starting the
# crash-looping services. sdhci-acpi is built-in but its probe defers until udev
# processes uevents; without this, /dev/mmcblk0 never appears. udev only loads
# drivers/firmware — it does NOT start shill/btmanagerd/dbus. ---
say "coldplug: starting udevd + trigger + settle (no services)"
mkdir -p /run/udev 2>/dev/null
if command -v udevd >/dev/null 2>&1; then udevd --daemon 2>/dev/null
elif [ -x /lib/systemd/systemd-udevd ]; then /lib/systemd/systemd-udevd --daemon 2>/dev/null
fi
udevadm trigger --type=subsystems --action=add 2>/dev/null
udevadm trigger --type=devices --action=add 2>/dev/null
udevadm settle --timeout=30 2>/dev/null
say "coldplug done"

# capture the kernel's storage/probe view to the persistent trace so we can
# diagnose eMMC enumeration offline on the build host.
dump_storage_dmesg() {
  { echo "===== dmesg (mmc/sdhci/i2c/lpss/dma/regulator/probe) @ $* ====="
    dmesg 2>/dev/null | grep -iE 'mmc|sdhci|i2c|lpss|idma|dw_dmac|dma|regulator|80860f|deferred|probe|clk'
    echo "===== /dev block devices ====="; ls -l /dev/mmc* /dev/sd* 2>/dev/null
    echo "===== mmc_host sysfs ====="; ls -l /sys/class/mmc_host/ 2>/dev/null; ls -l /sys/bus/platform/devices/ 2>/dev/null | grep -iE '80860f|sdhci|mmc'
  } >> "$TRACE" 2>&1
  sync
}
dump_storage_dmesg "after-coldplug"

# --- wait for the eMMC target to appear ---
w=0
while [ ! -b "$TARGET" ] && [ "$w" -lt 60 ]; do say "waiting for $TARGET ... ${w}s"; sleep 3; w=$((w+3)); done
if [ ! -b "$TARGET" ]; then
  dump_storage_dmesg "timeout-no-mmcblk0"
  finish "FATAL: $TARGET never appeared (dmesg captured to $TRACE)" 30
fi
say "$TARGET present"

# --- locate the USB (our boot disk) + its ESP (partition 12) ---
USB_DISK="$(rootdev -s -d 2>/dev/null)"
USB_ESP="$(partdev "$USB_DISK" 12)"
say "USB_DISK=$USB_DISK  USB_ESP=$USB_ESP"
mkdir -p "$UESP_MNT" "$EESP_MNT"
mount "$USB_ESP" "$UESP_MNT" 2>/dev/null && say "mounted USB ESP" || say "WARN: USB ESP mount failed (will retry before copy)"

# --- 1. install FydeOS to the eMMC, live output to console ---
say "running: chromeos-install --dst $TARGET --yes   (slow step; watch below)"
{ chromeos-install --dst "$TARGET" --yes; echo "$?" > /tmp/ic_rc; } 2>&1 | tee -a "$TRACE" > "$CON"
rc="$(cat /tmp/ic_rc 2>/dev/null || echo 1)"
[ "$rc" = "0" ] || finish "chromeos-install FAILED rc=$rc (eMMC left as-is, safe to retry)" 30
say "chromeos-install SUCCESS"

# --- 2. eMMC ROOT-A PARTUUID ---
ROOT_PARTUUID="$(cgpt show -i 3 -u "$TARGET" 2>/dev/null)"
say "eMMC ROOT-A PARTUUID=$ROOT_PARTUUID"
[ -n "$ROOT_PARTUUID" ] || finish "ERROR: no eMMC ROOT-A PARTUUID" 30

# --- 3. overwrite eMMC ESP with our 32-bit-UEFI boot chain ---
mountpoint -q "$UESP_MNT" 2>/dev/null || mount "$(partdev "$(rootdev -s -d)" 12)" "$UESP_MNT" 2>/dev/null
EMMC_ESP="$(partdev "$TARGET" 12)"
mount "$EMMC_ESP" "$EESP_MNT" 2>/dev/null || finish "FATAL: cannot mount eMMC ESP $EMMC_ESP" 30
mkdir -p "$EESP_MNT/syslinux" "$EESP_MNT/efi/boot" "$EESP_MNT/boot/grub"
cp -f "$UESP_MNT/syslinux/vmlinuz.A"    "$EESP_MNT/syslinux/vmlinuz.A"
cp -f "$UESP_MNT/efi/boot/bootia32.efi" "$EESP_MNT/efi/boot/bootia32.efi"
cp -f "$UESP_MNT/efi/boot/bootx64.efi"  "$EESP_MNT/efi/boot/bootx64.efi" 2>/dev/null || true
# also drop GRUB at the Windows Boot Manager path: the fixed eMMC boots only via
# the firmware's persistent NVRAM entry (-> \EFI\Microsoft\Boot\bootmgfw.efi),
# NOT the removable-media fallback that boots the USB. No efivarfs to add an
# NVRAM entry, so we occupy the path the existing entry already points to.
mkdir -p "$EESP_MNT/efi/microsoft/boot"
cp -f "$UESP_MNT/efi/boot/bootia32.efi" "$EESP_MNT/efi/microsoft/boot/bootmgfw.efi"

cat > "$EESP_MNT/boot/grub/grub.cfg" <<EOF
set timeout=2
set default=0
insmod part_gpt
insmod fat
insmod ext2
insmod linux
insmod all_video
insmod search_fs_file
search --no-floppy --file --set=root /syslinux/vmlinuz.A
menuentry "FydeOS A (W4-820 eMMC)" {
  linux /syslinux/vmlinuz.A init=/sbin/init rootwait ro noresume loglevel=4 noinitrd audit=0 cros_efi i915.enable_psr=0 i915.enable_fbc=0 i915.enable_dc=0 root=PARTUUID=$ROOT_PARTUUID
  boot
}
EOF

XLF="$(od -An -tx1 -j 566 -N2 "$EESP_MNT/syslinux/vmlinuz.A" | tr -s ' ')"
say "eMMC vmlinuz.A xloadflags=[$XLF] (want low byte 0x04 set, e.g. '3f 00')"
sync
umount "$EESP_MNT" 2>/dev/null
umount "$UESP_MNT" 2>/dev/null

finish "=== COMPLETE — install + ESP re-inject done. Remove USB, boot eMMC. ===" 15
