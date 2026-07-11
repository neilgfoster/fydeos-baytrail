#!/bin/sh
# Iconia W4-820 — audio diagnostic + tone test (PID 1), runs ON the eMMC (the #10
# modules with the RT5640 codec + bytcr_rt5640 machine driver live there; LoadPin
# forbids side-loading). CRAS has no UCM for this card (only sof-hda-dsp), so it
# stays silent. This dumps card/DSP/dmesg state, brute-unmutes every mixer control
# and plays a sine on each card so we can HEAR whether the hardware path works.
# Self-restores init=/sbin/init before powering off. Play tone = LISTEN to tablet.
export PATH=/usr/sbin:/usr/bin:/sbin:/bin
CON=/dev/tty1
TRACE=/baytrail-audio-diag.log

mount -t proc proc /proc 2>/dev/null
mount -t sysfs sys /sys 2>/dev/null
mount -t devtmpfs dev /dev 2>/dev/null
mount -t tmpfs run /run 2>/dev/null
mount -o remount,rw / 2>/dev/null || true

say() { _m="[$(date -u '+%H:%M:%S' 2>/dev/null)] $*"; echo "ICONIA $_m" > "$CON" 2>/dev/null||true; echo "$_m" >> "$TRACE" 2>/dev/null||true; sync 2>/dev/null||true; }
finish() { say "$1"; sync; sleep "${2:-10}"; poweroff -f 2>/dev/null; echo o > /proc/sysrq-trigger 2>/dev/null; while true; do sleep 60; done; }
partdev() { case "$1" in *[0-9]) echo "$1p$2";; *) echo "$1$2";; esac; }

n=0; while [ "$n" -lt 6 ]; do echo "" > "$CON"; echo "###### ICONIA AUDIO DIAG ######" > "$CON"; n=$((n+1)); done
say "=== baytrail-audio-diag.sh PID $$ ==="
mkdir -p /run/udev; udevd --daemon 2>/dev/null || /lib/systemd/systemd-udevd --daemon 2>/dev/null
udevadm trigger --action=add 2>/dev/null; udevadm settle --timeout=15 2>/dev/null

# make sure the audio stack is loaded (default paths = booted rootfs, LoadPin-ok)
for m in snd-soc-rt5640 snd-soc-sst-bytcr-rt5640 snd-soc-sst-atom-hifi2-platform \
         snd-soc-sst-acpi snd-intel-dspcfg snd-sof-acpi snd-sof-acpi-intel-byt; do
  modprobe "$m" 2>>"$TRACE"
done
udevadm settle --timeout=10 2>/dev/null; sleep 3

{
  echo "===== /proc/asound/cards ====="; cat /proc/asound/cards 2>/dev/null || echo "(none)"
  echo "===== aplay -l ====="; aplay -l 2>&1
  echo "===== dmesg audio ====="; dmesg 2>/dev/null | grep -iE 'sof|sst|rt5640|byt|atom|dsp|snd|asoc|firmware' | tail -50
} >> "$TRACE" 2>&1
sync

# --- brute-unmute every card and play a tone on each so we can hear which works ---
for cdir in /proc/asound/card[0-9]*; do
  [ -d "$cdir" ] || continue
  c=$(basename "$cdir" | sed 's/card//')
  cname=$(cat "/proc/asound/card$c/id" 2>/dev/null)
  say ">>> card $c ($cname): unmuting all controls"
  amixer -c "$c" scontrols 2>/dev/null | sed -n "s/^Simple mixer control '\(.*\)',\([0-9]*\)$/\1,\2/p" | while IFS= read -r line; do
    ctl=$(echo "$line" | sed 's/,[0-9]*$//')
    amixer -c "$c" sset "$ctl" unmute  >/dev/null 2>>"$TRACE"
    amixer -c "$c" sset "$ctl" on       >/dev/null 2>>"$TRACE"
    amixer -c "$c" sset "$ctl" 90%      >/dev/null 2>>"$TRACE"
  done
  amixer -c "$c" scontrols >> "$TRACE" 2>&1
  say ">>> card $c ($cname): PLAYING 440Hz sine — LISTEN (5s)"
  speaker-test -D "plughw:$c,0" -c 2 -t sine -f 440 -l 1 >> "$TRACE" 2>&1 &
  sp=$!; sleep 6; kill "$sp" 2>/dev/null
  say "    card $c done"
done

# --- self-restore normal boot ---
DISK="$(rootdev -s -d 2>/dev/null)"; ESP="$(partdev "$DISK" 12)"; mkdir -p /mnt/self-esp
if mount "$ESP" /mnt/self-esp 2>/dev/null; then
  sed -i 's#init=[^ ]*#init=/sbin/init#' /mnt/self-esp/boot/grub/grub.cfg 2>>"$TRACE"
  sync; umount /mnt/self-esp 2>/dev/null; say "restored init=/sbin/init on $ESP"
fi
finish "=== AUDIO DIAG DONE — did you hear a tone on any card? (this eMMC now boots normally) ===" 12
