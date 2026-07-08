#!/bin/sh
# Iconia W4-820 — restore /lib/modules onto the eMMC rootfs (PID 1, init= wrapper).
#
# WHY: session-16 deploy of the 6.6.99 (R144) module tree ran the eMMC rootfs out
# of space (2.7G, 0 free), so /lib/modules was relocated to stateful and replaced
# with a SYMLINK:  /lib/modules -> /mnt/stateful_partition/unencrypted/lib-modules
# That broke WiFi on BOTH kernels: brcmfmac (SDIO 02D0:4324) autoloads during very
# early coldplug, BEFORE stateful is mounted, so the symlink target doesn't exist,
# modprobe fails and is never retried -> no wlan on 6.6.76 or 6.6.99.
#
# FIX (all on eMMC ROOT-A): drop the symlink, copy the real 6.6.76 tree back from
# stateful so it lives on the rootfs and autoloads early like it used to. Re-create
# the 6.6.99 dir as a per-version symlink into stateful so the R144 TEST entry is
# still bootable (its own early-autoload timing is a separate, later problem).
#
# Run via init=/sbin/iconia-modules-restore.sh from the USB, then boot the eMMC.
export PATH=/usr/sbin:/usr/bin:/sbin:/bin
CON=/dev/tty1
KVER=6.6.76-gabcfb16364e1
KVER99=6.6.99-g7232af57f054
ROOTA_MNT=/mnt/iconia-eroota
STATE_MNT=/mnt/iconia-estate
STATE_SUB=unencrypted/lib-modules          # where session-16 staged both trees
TRACE=/mnt/iconia-eroota/iconia-modules-restore.log

mount -t proc proc /proc 2>/dev/null
mount -t sysfs sys /sys 2>/dev/null
mount -t devtmpfs dev /dev 2>/dev/null
mount -t tmpfs run /run 2>/dev/null
mount -o remount,rw / 2>/dev/null || true

say() { _m="[$(date -u '+%H:%M:%S' 2>/dev/null)] $*"; echo "ICONIA $_m" > "$CON" 2>/dev/null||true; echo "$_m" >> "$TRACE" 2>/dev/null||true; echo "ICONIA: $*" > /dev/kmsg 2>/dev/null||true; sync 2>/dev/null||true; }
# Halt with the result on screen (don't race to poweroff — that leaves us blind).
finish() { echo "" > "$CON"; echo "#### ICONIA MODULES-RESTORE — HALT ####" > "$CON"; say "$1"; say "=== read this, then hold power ~10s to shut down, remove USB, boot eMMC ==="; while true; do sleep 3600; done; }
partdev() { case "$1" in *[0-9]) echo "$1p$2";; *) echo "$1$2";; esac; }
find_emmc() { for d in /sys/block/mmcblk*; do b=$(basename "$d"); case "$b" in *boot*|*rpmb*) continue;; esac; sz=$(cat "$d/size" 2>/dev/null); [ "${sz:-0}" -gt 100000000 ] && { echo "/dev/$b"; return 0; }; done; return 1; }

n=0; while [ "$n" -lt 6 ]; do echo "" > "$CON"; echo "###### ICONIA MODULES RESTORE (eMMC) ######" > "$CON"; n=$((n+1)); done
say "=== iconia-modules-restore.sh PID $$ ==="

mkdir -p /run/udev; udevd --daemon 2>/dev/null || /lib/systemd/systemd-udevd --daemon 2>/dev/null
udevadm trigger --action=add 2>/dev/null; udevadm settle --timeout=10 2>/dev/null

# bring up eMMC (rebind sdhci-acpi; identity detection since rebinding renumbers)
DRV=/sys/bus/platform/drivers/sdhci-acpi; i=0; TARGET="$(find_emmc)"
while [ -z "$TARGET" ] && [ "$i" -lt 40 ]; do
  for base in 80860F14:00 80860F14:01; do [ -e "/sys/bus/platform/devices/$base" ] || continue; echo "$base" > "$DRV/unbind" 2>/dev/null; echo "$base" > "$DRV/bind" 2>/dev/null; done
  udevadm trigger --action=add 2>/dev/null; udevadm settle --timeout=5 2>/dev/null; sleep 2; i=$((i+1)); TARGET="$(find_emmc)"; say "ensure eMMC try $i: ${TARGET:-absent}"
done
[ -n "$TARGET" ] || finish "FATAL: no eMMC disk after $i tries — power-cycle & retry"
say "eMMC = $TARGET"

EROOTA="$(partdev "$TARGET" 3)"
ESTATE="$(partdev "$TARGET" 1)"
mkdir -p "$ROOTA_MNT" "$STATE_MNT"
mount "$EROOTA" "$ROOTA_MNT" 2>/dev/null || { TRACE=/iconia-modules-restore.log; finish "FATAL: cannot mount eMMC ROOT-A $EROOTA"; }
mount -o ro "$ESTATE" "$STATE_MNT" 2>/dev/null || finish "FATAL: cannot mount eMMC stateful $ESTATE"
say "ROOT-A=$EROOTA  stateful=$ESTATE"
say "ROOT-A free BEFORE: $(df -h "$ROOTA_MNT" 2>&1 | awk 'END{print $4}')"

SRC="$STATE_MNT/$STATE_SUB/$KVER"
[ -d "$SRC" ] || finish "FATAL: 6.6.76 module tree not found on stateful at $SRC"

LM="$ROOTA_MNT/lib/modules"
if [ -L "$LM" ]; then
  say "removing bad symlink $LM -> $(readlink "$LM" 2>/dev/null)"
  rm -f "$LM"
elif [ -d "$LM" ] && [ ! -e "$LM/$KVER/modules.dep" ]; then
  say "existing /lib/modules dir looks incomplete; leaving in place, will repopulate"
fi
mkdir -p "$LM"

# 1. copy the real 6.6.76 tree back onto the rootfs (so it autoloads early)
if [ -e "$LM/$KVER/modules.dep" ]; then
  say "6.6.76 tree already present on rootfs — skipping copy"
else
  say "copying $KVER tree from stateful -> rootfs (~200M, may be tight) ..."
  cp -a "$SRC" "$LM/" 2>>"$TRACE"
  RC=$?
  sync
  say "cp exit=$RC ; ROOT-A free AFTER copy: $(df -h "$ROOTA_MNT" 2>&1 | awk 'END{print $4}')"
  [ "$RC" = 0 ] || finish "FATAL: copy failed (RC=$RC) — likely OUT OF SPACE; tell me this line"
fi

# 2. keep the 6.6.99 (R144 TEST) tree reachable via a per-version symlink into
#    stateful (absolute path as seen once stateful is mounted at normal boot).
ln -sfn "/mnt/stateful_partition/$STATE_SUB/$KVER99" "$LM/$KVER99"
say "6.6.99 symlink: $(ls -ld "$LM/$KVER99" 2>&1)"

# 3. regenerate the 6.6.76 module index on the rootfs and verify WiFi autoload data
say "depmod $KVER (regenerating modules.dep/alias) ..."
depmod -b "$ROOTA_MNT" "$KVER" 2>&1 | tee -a "$TRACE" > /dev/null
DEPC=$(grep -c brcmfmac "$LM/$KVER/modules.dep" 2>/dev/null)
ALIC=$(grep -ic 'v02D0d4324' "$LM/$KVER/modules.alias" 2>/dev/null)
KO=$(ls "$LM/$KVER"/kernel/drivers/net/wireless/broadcom/brcm80211/brcmfmac/brcmfmac.ko* 2>/dev/null)
say "post: brcmfmac.ko='$KO'  modules.dep brcmfmac=$DEPC  alias 4324=$ALIC (all should be >0)"

sync
umount "$STATE_MNT" 2>/dev/null
umount "$ROOTA_MNT" 2>/dev/null

if [ -n "$KO" ] && [ "${DEPC:-0}" -gt 0 ] && [ "${ALIC:-0}" -gt 0 ]; then
  finish "*** MODULES RESTORE OK — /lib/modules real on rootfs, brcmfmac indexed. Boot eMMC (default FydeOS A) — WiFi should return ***"
else
  finish "!!! RESTORE INCOMPLETE — brcmfmac/alias missing (ko='$KO' dep=$DEPC alias=$ALIC) — tell me this line before booting eMMC !!!"
fi
