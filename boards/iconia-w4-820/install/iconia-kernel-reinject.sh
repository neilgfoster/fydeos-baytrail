#!/bin/sh
# Iconia W4-820 — re-inject the rebuilt Bay Trail kernel+modules to eMMC (PID 1).
#
# After rebuilding 6.6.76 with baytrail-hw.config (backlight PMIC PWM, i2c
# semaphore, regulators, FW_LOADER_COMPRESS_XZ), push the new vmlinuz + module
# set onto the eMMC. Reads the new modules tar from the USB STATE partition (p1)
# and the new vmlinuz from the USB ESP (p12), writes them to eMMC ROOT-A (p3) and
# eMMC ESP (p12), runs depmod ON-DEVICE (tablet depmod handles .ko.gz), verifies,
# powers off. Boot the eMMC afterward to test the new kernel.
export PATH=/usr/sbin:/usr/bin:/sbin:/bin
CON=/dev/tty1
KV=6.6.76-gabcfb16364e1
TAR=modules-baytrail.tar
USTATE_MNT=/mnt/iconia-ustate
UESP_MNT=/mnt/iconia-uesp
EROOTA_MNT=/mnt/iconia-eroota
EESP_MNT=/mnt/iconia-eesp
TRACE=/iconia-kernel-reinject.log

mount -t proc proc /proc 2>/dev/null
mount -t sysfs sys /sys 2>/dev/null
mount -t devtmpfs dev /dev 2>/dev/null
mount -t tmpfs run /run 2>/dev/null
mount -o remount,rw / 2>/dev/null || true

say() { _m="[$(date -u '+%H:%M:%S' 2>/dev/null)] $*"; echo "ICONIA $_m" > "$CON" 2>/dev/null||true; echo "$_m" >> "$TRACE" 2>/dev/null||true; echo "ICONIA: $*" > /dev/kmsg 2>/dev/null||true; sync 2>/dev/null||true; }
finish() { say "$1"; say "powering off in ${2:-10}s"; sync; sleep "${2:-10}"; poweroff -f 2>/dev/null; echo o > /proc/sysrq-trigger 2>/dev/null; while true; do sleep 60; done; }
partdev() { case "$1" in *[0-9]) echo "$1p$2";; *) echo "$1$2";; esac; }
find_emmc() { for d in /sys/block/mmcblk*; do b=$(basename "$d"); case "$b" in *boot*|*rpmb*) continue;; esac; sz=$(cat "$d/size" 2>/dev/null); [ "${sz:-0}" -gt 100000000 ] && { echo "/dev/$b"; return 0; }; done; return 1; }

n=0; while [ "$n" -lt 6 ]; do echo "" > "$CON"; echo "#### ICONIA KERNEL RE-INJECT (Bay Trail) ####" > "$CON"; n=$((n+1)); done
say "=== iconia-kernel-reinject.sh PID $$ ==="

mkdir -p /run/udev; udevd --daemon 2>/dev/null || /lib/systemd/systemd-udevd --daemon 2>/dev/null
udevadm trigger --action=add 2>/dev/null; udevadm settle --timeout=10 2>/dev/null

# --- bring up eMMC (rebind sdhci-acpi; identity detect) ---
DRV=/sys/bus/platform/drivers/sdhci-acpi; i=0; TARGET="$(find_emmc)"
while [ -z "$TARGET" ] && [ "$i" -lt 40 ]; do
  for base in 80860F14:00 80860F14:01; do [ -e "/sys/bus/platform/devices/$base" ] || continue; echo "$base" > "$DRV/unbind" 2>/dev/null; echo "$base" > "$DRV/bind" 2>/dev/null; done
  udevadm trigger --action=add 2>/dev/null; udevadm settle --timeout=5 2>/dev/null; sleep 2; i=$((i+1)); TARGET="$(find_emmc)"; say "ensure eMMC try $i: ${TARGET:-absent}"
done
[ -n "$TARGET" ] || finish "FATAL: no eMMC after $i tries — power-cycle & retry" 20
say "eMMC = $TARGET"

# --- locate USB (boot disk) partitions: STATE=p1 (has the tar), ESP=p12 (new vmlinuz) ---
USB_DISK="$(rootdev -s -d)"
USTATE="$(partdev "$USB_DISK" 1)"; UESP="$(partdev "$USB_DISK" 12)"
mkdir -p "$USTATE_MNT" "$UESP_MNT" "$EROOTA_MNT" "$EESP_MNT"
mount "$USTATE" "$USTATE_MNT" 2>/dev/null || finish "FATAL: cannot mount USB STATE $USTATE (tar source)" 20
mount "$UESP" "$UESP_MNT" 2>/dev/null || finish "FATAL: cannot mount USB ESP $UESP" 20
[ -f "$USTATE_MNT/$TAR" ] || finish "FATAL: $TAR not found on USB STATE — stage it first" 20
say "found modules tar + USB ESP"

# --- mount eMMC ROOT-A and replace the module tree ---
EROOTA="$(partdev "$TARGET" 3)"
mount "$EROOTA" "$EROOTA_MNT" 2>/dev/null || finish "FATAL: cannot mount eMMC ROOT-A $EROOTA" 20
say "replacing /lib/modules/$KV on eMMC ..."
rm -rf "$EROOTA_MNT/lib/modules/$KV"
# Reclaim space: the rootfs ships BOTH decompressed firmware and .xz copies, and
# the kernel now loads .xz natively (FW_LOADER_COMPRESS_XZ) — so any file with an
# .xz sibling is a removable dupe. i915-as-a-module grew the tar (~+46M) and
# overran eMMC ROOT-A; this frees far more than that. (2026-07-03)
say "free before reclaim: $(df -h "$EROOTA_MNT" 2>/dev/null | awk 'END{print $4}')"
# (a) decompressed firmware that has an .xz sibling = removable dupe
find "$EROOTA_MNT/lib/firmware" -type f ! -name '*.xz' 2>/dev/null | while read -r f; do [ -f "$f.xz" ] && rm -f "$f"; done
# (b) firmware for hardware this Bay Trail tablet does NOT have (Intel gfx +
#     Broadcom wifi only). Frees hundreds of MB so the i915-as-module tree fits.
#     KEEP: i915, brcm (wifi), regulatory.db, intel SST/SOF (audio), edid.
for d in amdgpu radeon amd nvidia nvidiagpu mrvl ath10k ath11k ath12k ath6k \
         mediatek mrvlprestera qed qcom qca rtlwifi rtw88 rtw89 rtl_bt libertas \
         iwlwifi ti-connectivity cypress cxgb4 netronome liquidio dpaa2 \
         bnx2x bnx2 cavium myricom emi62 emi26 korg keyspan dabusb ttusb-budget \
         cpia2 av7110 vpu powervr qat_* imx; do
  rm -rf "$EROOTA_MNT/lib/firmware/$d"
done
sync
say "free after reclaim:  $(df -h "$EROOTA_MNT" 2>/dev/null | awk 'END{print $4}')"
tar xf "$USTATE_MNT/$TAR" -C "$EROOTA_MNT" 2>>"$TRACE" || finish "FATAL: tar extract failed (still out of space?)" 20
say "depmod $KV on-device ..."
depmod -b "$EROOTA_MNT" "$KV" 2>>"$TRACE"
DEPC=$(grep -c brcmfmac "$EROOTA_MNT/lib/modules/$KV/modules.dep" 2>/dev/null)
say "post-depmod modules.dep brcmfmac=$DEPC (should be >0)"
sync
umount "$EROOTA_MNT" 2>/dev/null

# --- copy new vmlinuz to eMMC ESP ---
mount "$(partdev "$TARGET" 12)" "$EESP_MNT" 2>/dev/null || finish "FATAL: cannot mount eMMC ESP" 20
cp -f "$UESP_MNT/syslinux/vmlinuz.A" "$EESP_MNT/syslinux/vmlinuz.A"
XLF="$(od -An -tx1 -j 566 -N2 "$EESP_MNT/syslinux/vmlinuz.A" | tr -s ' ')"
say "new eMMC vmlinuz xloadflags=[$XLF] (want '3f 00')"
sync
umount "$EESP_MNT" 2>/dev/null; umount "$UESP_MNT" 2>/dev/null; umount "$USTATE_MNT" 2>/dev/null

finish "=== KERNEL RE-INJECT DONE — remove USB, boot eMMC (new Bay Trail kernel) ===" 12
