#!/bin/sh
# Iconia W4-820 — enable Wi-Fi (and decompress audio fw) on the eMMC (PID 1).
#
# Three root causes fixed, all on eMMC ROOT-A:
#  1. STALE MODULE INDEX: modules.dep/alias don't list brcmfmac (0 hits) after we
#     injected the 6.6.76 modules, so modprobe/udev can't load or autoload it.
#     -> run depmod to regenerate the index (module autoload + sdio alias).
#  2. .xz FIRMWARE can't load: CONFIG_FW_LOADER_COMPRESS is unset but firmware
#     ships only as .xz, so request_firmware(<name>.bin) fails -2. -> decompress
#     the BCM43241 firmware (chip = SDIO 02D0:4324) in place.
#  3. BOARD NVRAM MISSING: brcmfmac wants brcmfmac43241b4-sdio.<sys_vendor>-<product>
#     .txt = "Acer-Iconia W4-820P". -> create it from the Bay Trail reference
#     NVRAM (Intel VALLEYVIEW C0), plus a generic fallback.
#
# Run via init=/sbin/iconia-wifi-fix.sh from the USB, then boot the eMMC -> udev
# autoloads brcmfmac -> firmware+nvram load -> wlanX at OOBE.
export PATH=/usr/sbin:/usr/bin:/sbin:/bin
CON=/dev/tty1
KVER=6.6.76-gabcfb16364e1
ROOTA_MNT=/mnt/iconia-eroota
TRACE=/iconia-wifi-fix.log

mount -t proc proc /proc 2>/dev/null
mount -t sysfs sys /sys 2>/dev/null
mount -t devtmpfs dev /dev 2>/dev/null
mount -t tmpfs run /run 2>/dev/null
mount -o remount,rw / 2>/dev/null || true

say() { _m="[$(date -u '+%H:%M:%S' 2>/dev/null)] $*"; echo "ICONIA $_m" > "$CON" 2>/dev/null||true; echo "$_m" >> "$TRACE" 2>/dev/null||true; echo "ICONIA: $*" > /dev/kmsg 2>/dev/null||true; sync 2>/dev/null||true; }
finish() { say "$1"; say "powering off in ${2:-10}s"; sync; sleep "${2:-10}"; poweroff -f 2>/dev/null; echo o > /proc/sysrq-trigger 2>/dev/null; while true; do sleep 60; done; }
partdev() { case "$1" in *[0-9]) echo "$1p$2";; *) echo "$1$2";; esac; }
find_emmc() { for d in /sys/block/mmcblk*; do b=$(basename "$d"); case "$b" in *boot*|*rpmb*) continue;; esac; sz=$(cat "$d/size" 2>/dev/null); [ "${sz:-0}" -gt 100000000 ] && { echo "/dev/$b"; return 0; }; done; return 1; }

n=0; while [ "$n" -lt 6 ]; do echo "" > "$CON"; echo "###### ICONIA WIFI FIX (eMMC) ######" > "$CON"; n=$((n+1)); done
say "=== iconia-wifi-fix.sh PID $$ ==="

mkdir -p /run/udev; udevd --daemon 2>/dev/null || /lib/systemd/systemd-udevd --daemon 2>/dev/null
udevadm trigger --action=add 2>/dev/null; udevadm settle --timeout=10 2>/dev/null

# bring up eMMC (rebind sdhci-acpi; identity detection since rebinding renumbers)
DRV=/sys/bus/platform/drivers/sdhci-acpi; i=0; TARGET="$(find_emmc)"
while [ -z "$TARGET" ] && [ "$i" -lt 40 ]; do
  for base in 80860F14:00 80860F14:01; do [ -e "/sys/bus/platform/devices/$base" ] || continue; echo "$base" > "$DRV/unbind" 2>/dev/null; echo "$base" > "$DRV/bind" 2>/dev/null; done
  udevadm trigger --action=add 2>/dev/null; udevadm settle --timeout=5 2>/dev/null; sleep 2; i=$((i+1)); TARGET="$(find_emmc)"; say "ensure eMMC try $i: ${TARGET:-absent}"
done
[ -n "$TARGET" ] || finish "FATAL: no eMMC disk after $i tries — power-cycle & retry" 20
say "eMMC = $TARGET"

EROOTA="$(partdev "$TARGET" 3)"
mkdir -p "$ROOTA_MNT"
mount "$EROOTA" "$ROOTA_MNT" 2>/dev/null || finish "FATAL: cannot mount eMMC ROOT-A $EROOTA" 20

# 1. regenerate the module index for the eMMC rootfs
say "depmod $KVER (regenerating modules.dep/alias) ..."
depmod -b "$ROOTA_MNT" "$KVER" 2>&1 | tee -a "$TRACE" > /dev/null
DEPC=$(grep -c brcmfmac "$ROOTA_MNT/lib/modules/$KVER/modules.dep" 2>/dev/null)
ALIC=$(grep -ic 'v02D0d4324' "$ROOTA_MNT/lib/modules/$KVER/modules.alias" 2>/dev/null)
say "post-depmod: modules.dep brcmfmac=$DEPC  alias 4324=$ALIC (both should be >0)"

# 2. decompress BCM43241 firmware + audio firmware in place (.xz -> plain)
FW="$ROOTA_MNT/lib/firmware/brcm"
for f in brcmfmac43241b0-sdio.bin brcmfmac43241b4-sdio.bin brcmfmac43241b5-sdio.bin; do
  [ -f "$FW/$f.xz" ] && xz -dkf "$FW/$f.xz" && say "decompressed $f"
done
IFW="$ROOTA_MNT/lib/firmware/intel"
[ -f "$IFW/fw_sst_0f28.bin.xz" ] && xz -dkf "$IFW/fw_sst_0f28.bin.xz" && say "decompressed fw_sst_0f28.bin (audio)"

# 3. board NVRAM: from the Bay Trail reference (Intel VALLEYVIEW C0), named for DMI
NVSRC="$FW/brcmfmac43241b4-sdio.Intel Corp.-VALLEYVIEW C0 PLATFORM.txt"
[ -f "$NVSRC.xz" ] && xz -dkf "$NVSRC.xz"
if [ -f "$NVSRC" ]; then
  cp -f "$NVSRC" "$FW/brcmfmac43241b4-sdio.Acer-Iconia W4-820P.txt"
  cp -f "$NVSRC" "$FW/brcmfmac43241b4-sdio.txt"          # generic fallback
  say "installed NVRAM: 'Acer-Iconia W4-820P' + generic (from VALLEYVIEW C0)"
else
  say "WARN: reference NVRAM not found to seed board NVRAM"
fi

{ echo "--- brcm firmware (uncompressed .bin/.txt present?) ---"; ls -la "$FW"/brcmfmac43241b4-sdio.bin "$FW"/brcmfmac43241b4-sdio*.txt 2>&1; } >> "$TRACE" 2>&1
sync
umount "$ROOTA_MNT" 2>/dev/null
finish "=== WIFI FIX DONE — remove USB, boot eMMC, check for Wi-Fi at OOBE ===" 12
