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

# load a module with a hard timeout so a wedging driver can't hang the whole diag,
# and log exactly which one hangs.
try_modprobe() {
  say "modprobe $1 ..."
  ( modprobe "$1" 2>>"$TRACE" ) & mp=$!
  c=0; while kill -0 "$mp" 2>/dev/null && [ "$c" -lt 12 ]; do sleep 1; c=$((c+1)); done
  if kill -0 "$mp" 2>/dev/null; then kill -9 "$mp" 2>/dev/null; say "  !! $1 HUNG (killed after ${c}s)"; else say "  $1 ok"; fi
}
dump() { { echo; echo "===== $1 ====="; shift; eval "$@"; } >> "$TRACE" 2>&1; sync; }

say "coldplug (udev autoload, settle<=20s) ..."
mkdir -p /run/udev; udevd --daemon 2>/dev/null || /lib/systemd/systemd-udevd --daemon 2>/dev/null
udevadm trigger --action=add 2>/dev/null
udevadm settle --timeout=20 2>/dev/null
say "coldplug settle returned"

# capture what udev already autoloaded BEFORE the risky manual loads, so we keep
# data even if a manual modprobe wedges.
dump "uname" "uname -a"
dump "autoloaded modules (of interest)" "grep -iE 'brcmfmac|cfg80211|mac80211|bluetooth|btbcm|hci|snd|sst|rt5640|soc|kxcjk|iio|industrialio|backlight|pwm|axp' /proc/modules"
dump "WIFI"   "ls -l /sys/class/net/ 2>/dev/null; iw dev 2>/dev/null"
dump "AUDIO (pre)"    "cat /proc/asound/cards 2>/dev/null; ls -l /sys/class/sound/ 2>/dev/null"
dump "SENSORS (pre)"  "for d in /sys/bus/iio/devices/*; do [ -e \"\$d\" ] || continue; echo \"\$d name=\$(cat \$d/name 2>/dev/null)\"; done"
dump "BACKLIGHT" "for b in /sys/class/backlight/*; do [ -e \"\$b\" ] || continue; echo \"\$b \$(cat \$b/brightness 2>/dev/null)/\$(cat \$b/max_brightness 2>/dev/null)\"; done"
say "pre-dump done; now trying explicit module loads (each timed) ..."

for m in kxcjk_1013 pwm_lpss_platform btbcm hci_uart bluetooth snd_soc_sst_bytcr_rt5640 snd_intel_sst_acpi snd_soc_sst_acpi; do
  try_modprobe "$m"
done
sleep 8

dump "AUDIO (post)" "cat /proc/asound/cards 2>/dev/null; aplay -l 2>/dev/null"
dump "BLUETOOTH" "ls -l /sys/class/bluetooth/ 2>/dev/null; hciconfig -a 2>/dev/null"
dump "SENSORS/IIO (post)" "for d in /sys/bus/iio/devices/*; do [ -e \"\$d\" ] || continue; echo \"\$d name=\$(cat \$d/name 2>/dev/null)\"; done"
dump "dmesg firmware failures" "dmesg 2>/dev/null | grep -iE 'firmware|failed to load|direct firmware' | tail -40"
dump "dmesg audio/bt/sensor/backlight" "dmesg 2>/dev/null | grep -iE 'sst|rt5640|ASoC|snd|bluetooth|btbcm|hci|kxcjk|accel|iio|backlight|pwm' | tail -60"
say "captured to $TRACE"
finish "=== HW DIAG DONE — power off, read the log ===" 10
