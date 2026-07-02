#!/bin/sh
# Iconia W4-820 — make the eMMC bootable after install (init= wrapper, PID 1).
#
# "No bootable device": the firmware boots the fixed eMMC only via its NVRAM
# "Windows Boot Manager" entry (-> \EFI\Microsoft\Boot\bootmgfw.efi), not the
# removable-media fallback (\EFI\BOOT\BOOTIA32.EFI) that let the USB boot.
# chromeos-install wiped the Windows ESP, so that file is gone. This kernel has
# no efivarfs (CONFIG_EFIVAR_FS unset) so we can't add an NVRAM entry — instead
# we drop our GRUB at the path the existing entry already points to. Our GRUB
# reads /boot/grub/grub.cfg on the same ESP, which the installer already set up.
#
# Runs standalone via init=/sbin/iconia-fixboot.sh, mounts the eMMC ESP, installs
# bootmgfw.efi, logs to ROOT-A trace + console, and powers off. Non-destructive.
export PATH=/usr/sbin:/usr/bin:/sbin:/bin
CON=/dev/tty1
TARGET=/dev/mmcblk0
EESP_MNT=/mnt/iconia-eesp
TRACE=/iconia-fixboot.log

mount -t proc proc /proc 2>/dev/null
mount -t sysfs sys /sys 2>/dev/null
mount -t devtmpfs dev /dev 2>/dev/null
mount -t tmpfs run /run 2>/dev/null
mount -o remount,rw / 2>/dev/null || true

say() {
  _m="[$(date -u '+%H:%M:%S' 2>/dev/null)] $*"
  echo "ICONIA $_m" > "$CON" 2>/dev/null || true
  echo "$_m" >> "$TRACE" 2>/dev/null || true
  echo "ICONIA: $*" > /dev/kmsg 2>/dev/null || true
  sync 2>/dev/null || true
}
finish() { say "$1"; say "powering off in ${2:-10}s"; sync; sleep "${2:-10}"; poweroff -f 2>/dev/null; echo o > /proc/sysrq-trigger 2>/dev/null; while true; do sleep 60; done; }
partdev() { case "$1" in *[0-9]) echo "$1p$2" ;; *) echo "$1$2" ;; esac; }

n=0; while [ "$n" -lt 6 ]; do echo "" > "$CON"; echo "###### ICONIA FIXBOOT (eMMC bootable) ######" > "$CON"; n=$((n+1)); done
say "=== iconia-fixboot.sh PID $$ ==="

# coldplug so the eMMC enumerates (built-in sdhci probe defers without udev)
mkdir -p /run/udev; udevd --daemon 2>/dev/null || /lib/systemd/systemd-udevd --daemon 2>/dev/null
udevadm trigger --action=add 2>/dev/null; udevadm settle --timeout=30 2>/dev/null

w=0; while [ ! -b "$TARGET" ] && [ "$w" -lt 60 ]; do say "waiting for $TARGET ${w}s"; sleep 3; w=$((w+3)); done
[ -b "$TARGET" ] || finish "FATAL: $TARGET never appeared — power-cycle and retry" 20
say "$TARGET present"

EMMC_ESP="$(partdev "$TARGET" 12)"
mkdir -p "$EESP_MNT"
mount "$EMMC_ESP" "$EESP_MNT" 2>/dev/null || finish "FATAL: cannot mount eMMC ESP $EMMC_ESP" 20

if [ ! -f "$EESP_MNT/efi/boot/bootia32.efi" ]; then
  finish "FATAL: /efi/boot/bootia32.efi missing on eMMC ESP — install may be incomplete" 20
fi
mkdir -p "$EESP_MNT/efi/microsoft/boot"
cp -f "$EESP_MNT/efi/boot/bootia32.efi" "$EESP_MNT/efi/microsoft/boot/bootmgfw.efi"
say "installed bootmgfw.efi (Windows Boot Manager path) on eMMC ESP"

{ echo "--- eMMC ESP tree ---"; ls -laR "$EESP_MNT"; } >> "$TRACE" 2>&1
sync
umount "$EESP_MNT" 2>/dev/null
finish "=== FIXBOOT DONE — remove USB, boot eMMC ===" 12
