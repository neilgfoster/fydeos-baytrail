#!/bin/sh
# Iconia W4-820 — batch hardware diagnostic (PID 1, init= wrapper).
#
# Self-fixes THIS rootfs (depmod + decompress firmware) so module autoload is
# representative of a fixed system, does a full udev coldplug, then dumps the
# state of every remaining subsystem (audio / bluetooth / sensors / backlight /
# wifi) to a ROOT-A trace so we can batch the next fixes. Runs on the USB rootfs;
# results mirror the eMMC (same modules/firmware).
export PATH=/usr/sbin:/usr/bin:/sbin:/bin
CON=/dev/tty1
KVER=6.6.76-gabcfb16364e1
TRACE=/iconia-hw-diag.log

mount -t proc proc /proc 2>/dev/null
mount -t sysfs sys /sys 2>/dev/null
mount -t devtmpfs dev /dev 2>/dev/null
mount -t tmpfs run /run 2>/dev/null
mount -o remount,rw / 2>/dev/null || true

say() { _m="[$(date -u '+%H:%M:%S' 2>/dev/null)] $*"; echo "ICONIA $_m" > "$CON" 2>/dev/null||true; echo "$_m" >> "$TRACE" 2>/dev/null||true; echo "ICONIA: $*" > /dev/kmsg 2>/dev/null||true; sync 2>/dev/null||true; }
finish() { say "$1"; sync; sleep "${2:-12}"; poweroff -f 2>/dev/null; echo o > /proc/sysrq-trigger 2>/dev/null; while true; do sleep 60; done; }

n=0; while [ "$n" -lt 6 ]; do echo "" > "$CON"; echo "###### ICONIA HW DIAG (batch) ######" > "$CON"; n=$((n+1)); done
say "=== iconia-hw-diag.sh PID $$ ==="

# self-fix so autoload is representative: regenerate index + decompress firmware
say "depmod + decompress firmware (self-fix this rootfs) ..."
depmod "$KVER" 2>&1 | tee -a "$TRACE" >/dev/null
for x in /lib/firmware/brcm/*.xz /lib/firmware/intel/fw_sst_0f28.bin.xz; do
  [ -f "$x" ] && xz -dkf "$x" 2>/dev/null
done
# seed wifi nvram (harmless if already there)
NV="/lib/firmware/brcm/brcmfmac43241b4-sdio.Intel Corp.-VALLEYVIEW C0 PLATFORM.txt"
[ -f "$NV" ] && cp -f "$NV" "/lib/firmware/brcm/brcmfmac43241b4-sdio.Acer-Iconia W4-820P.txt" 2>/dev/null

say "coldplug (udev autoload) ..."
mkdir -p /run/udev; udevd --daemon 2>/dev/null || /lib/systemd/systemd-udevd --daemon 2>/dev/null
udevadm trigger --action=add 2>/dev/null; udevadm settle --timeout=20 2>/dev/null
# nudge subsystems that may need explicit load
for m in brcmfmac snd_soc_sst_bytcr_rt5640 snd_intel_sst_acpi snd_soc_sst_acpi kxcjk_1013 hci_uart btbcm bluetooth pwm_lpss_platform; do modprobe "$m" 2>/dev/null; done
say "settling 15s ..."
sleep 15

{
  echo "===== uname ====="; uname -a
  echo; echo "===== loaded modules (of interest) ====="
  grep -iE 'brcmfmac|cfg80211|mac80211|bluetooth|btbcm|hci|snd|sst|rt5640|soc|kxcjk|iio|industrialio|backlight|pwm|axp' /proc/modules
  echo; echo "===== WIFI ====="; ls -l /sys/class/net/ 2>/dev/null; iw dev 2>/dev/null
  echo; echo "===== BLUETOOTH ====="; ls -l /sys/class/bluetooth/ 2>/dev/null; hciconfig -a 2>/dev/null
  echo; echo "===== AUDIO ====="; cat /proc/asound/cards 2>/dev/null; ls -l /sys/class/sound/ 2>/dev/null; aplay -l 2>/dev/null
  echo; echo "===== SENSORS / IIO ====="; for d in /sys/bus/iio/devices/*; do [ -e "$d" ] || continue; echo "-- $d name=$(cat "$d/name" 2>/dev/null)"; done
  echo; echo "===== BACKLIGHT ====="; for b in /sys/class/backlight/*; do [ -e "$b" ] || continue; echo "-- $b bright=$(cat "$b/brightness" 2>/dev/null)/$(cat "$b/max_brightness" 2>/dev/null)"; done
  echo; echo "===== dmesg: firmware failures ====="; dmesg 2>/dev/null | grep -iE 'firmware|failed to load|direct firmware' | tail -40
  echo; echo "===== dmesg: audio/bt/sensor/backlight ====="; dmesg 2>/dev/null | grep -iE 'sst|rt5640|ASoC|snd|bluetooth|btbcm|hci|kxcjk|accel|iio|backlight|pwm' | tail -60
} >> "$TRACE" 2>&1
sync
say "captured to $TRACE"
finish "=== HW DIAG DONE — power off, read the log ===" 10
