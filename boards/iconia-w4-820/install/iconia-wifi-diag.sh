#!/bin/sh
# Iconia W4-820 — Wi-Fi diagnostic (PID 1, init= wrapper). READ-ONLY.
#
# Loads brcmfmac and captures what it actually asks for, so we can fix Wi-Fi
# precisely. Suspected root cause: CONFIG_FW_LOADER_COMPRESS is unset but the
# rootfs ships only .xz-compressed firmware, so request_firmware() for
# "brcmfmac43241b4-sdio.bin" fails with -2 (only the .bin.xz exists). This dumps:
#   * the tablet DMI strings (brcmfmac builds the NVRAM filename from these)
#   * dmesg brcmfmac/firmware lines (exact chip + firmware + nvram names it wants)
#   * SDIO device IDs, loaded modules, wlanX presence
# to a trace on ROOT-A, then powers off. Makes NO changes.
export PATH=/usr/sbin:/usr/bin:/sbin:/bin
CON=/dev/tty1
TRACE=/iconia-wifi-diag.log

mount -t proc proc /proc 2>/dev/null
mount -t sysfs sys /sys 2>/dev/null
mount -t devtmpfs dev /dev 2>/dev/null
mount -t tmpfs run /run 2>/dev/null
mount -o remount,rw / 2>/dev/null || true

say() { _m="[$(date -u '+%H:%M:%S' 2>/dev/null)] $*"; echo "ICONIA $_m" > "$CON" 2>/dev/null||true; echo "$_m" >> "$TRACE" 2>/dev/null||true; echo "ICONIA: $*" > /dev/kmsg 2>/dev/null||true; sync 2>/dev/null||true; }
finish() { say "$1"; sync; sleep "${2:-12}"; poweroff -f 2>/dev/null; echo o > /proc/sysrq-trigger 2>/dev/null; while true; do sleep 60; done; }

n=0; while [ "$n" -lt 6 ]; do echo "" > "$CON"; echo "###### ICONIA WIFI DIAG (read-only) ######" > "$CON"; n=$((n+1)); done
say "=== iconia-wifi-diag.sh PID $$ ==="

mkdir -p /run/udev; udevd --daemon 2>/dev/null || /lib/systemd/systemd-udevd --daemon 2>/dev/null
udevadm trigger --action=add 2>/dev/null; udevadm settle --timeout=15 2>/dev/null

say "loading brcmfmac ..."
modprobe brcmutil 2>&1 | tee -a "$TRACE" > /dev/null
modprobe cfg80211 2>&1 | tee -a "$TRACE" > /dev/null
modprobe brcmfmac 2>&1 | tee -a "$TRACE" > /dev/null
say "waiting 12s for firmware/SDIO ..."
sleep 12

{
  echo "===== DMI (brcmfmac NVRAM name = brcmfmac<chip>-sdio.<sys_vendor>-<product_name>.txt) ====="
  for f in sys_vendor product_name product_version board_vendor board_name bios_version; do
    printf '%s = ' "$f"; cat "/sys/class/dmi/id/$f" 2>/dev/null
  done
  echo "===== loaded brcm/cfg80211 modules ====="; grep -iE 'brcm|cfg80211|mac80211' /proc/modules
  echo "===== SDIO devices (vendor/device id) ====="
  for d in /sys/bus/sdio/devices/*; do [ -e "$d" ] || continue; echo "-- $d"; cat "$d/uevent" 2>/dev/null; done
  echo "===== net interfaces ====="; ls -l /sys/class/net/ 2>/dev/null
  echo "===== dmesg brcmfmac/firmware/sdio ====="
  dmesg 2>/dev/null | grep -iE 'brcmfmac|brcmutil|cfg80211|nvram|firmware|BCM43|sdio|mmc2|wlan|Direct firmware|clm_blob'
} >> "$TRACE" 2>&1
sync
say "diag captured to $TRACE"
finish "=== WIFI DIAG DONE — power off, read the log ===" 10
