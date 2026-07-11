#!/bin/sh
# Iconia W4-820 — WiFi-on-6.6.99 diagnostic (PID 1, init= wrapper). READ-ONLY.
#
# WHY: the R144 (6.6.99) kernel boots on the tablet but WiFi is dead, and 6.6.99
# kills SSH (brcmfmac down) so we can't inspect it live. This boots the USB's OWN
# (working) kernel — so it CANNOT bootloop — mounts the eMMC read-only, and dumps
# everything needed to decide WHY the 6.6.99 brcmfmac won't bring up wlan:
#   1. does the 6.6.99 driver reference a firmware blob we haven't staged? (b4 vs b5)
#   2. or does it reference the SAME blobs as the working 6.6.76 driver? (=> the
#      problem is load-TIMING: the 6.6.99 tree is symlinked to stateful and brcmfmac
#      coldplugs before stateful mounts — a firmware fix would be a red herring)
# It also captures the SDIO alias, the dep chain (are all deps present in the tree?),
# and what firmware is actually staged on the rootfs. All output -> the USB
# (/baytrail-wifi99-diag.log); nothing on the eMMC is modified.
#
# Run via init=/sbin/baytrail-wifi99-diag.sh from the USB, read the log on the laptop.
export PATH=/usr/sbin:/usr/bin:/sbin:/bin
CON=/dev/tty1
KVER=6.6.76-gabcfb16364e1
KVER99=6.6.99-g7232af57f054
ROOTA_MNT=/mnt/baytrail-eroota
STATE_MNT=/mnt/baytrail-estate
STATE_SUB=unencrypted/lib-modules
TRACE=/baytrail-wifi99-diag.log          # on the USB root (bring to laptop)
SDIO_ALIAS='v02D0d4324'                # brcmfmac SDIO 02D0:4324

mount -t proc proc /proc 2>/dev/null
mount -t sysfs sys /sys 2>/dev/null
mount -t devtmpfs dev /dev 2>/dev/null
mount -t tmpfs run /run 2>/dev/null
mount -o remount,rw / 2>/dev/null || true
: > "$TRACE" 2>/dev/null || TRACE=/tmp/baytrail-wifi99-diag.log

say() { _m="[$(date -u '+%H:%M:%S' 2>/dev/null)] $*"; echo "ICONIA $_m" > "$CON" 2>/dev/null||true; echo "$_m" >> "$TRACE" 2>/dev/null||true; sync 2>/dev/null||true; }
log() { echo "$*" >> "$TRACE" 2>/dev/null||true; }               # log-only (verbose)
hdr() { log ""; log "======== $* ========"; }
finish() { echo "" > "$CON"; echo "#### ICONIA WIFI99 DIAG — HALT ####" > "$CON"; say "$1"; say "=== log written to USB: $TRACE — hold power ~10s, remove USB, read it on the laptop ==="; sync; while true; do sleep 3600; done; }
partdev() { case "$1" in *[0-9]) echo "$1p$2";; *) echo "$1$2";; esac; }
# mount read-only, tolerating an unreplayed ext4 journal (ro,noload) — a plain
# `-o ro` fails on a dirty journal because it can't recover it while read-only.
mount_ro() { _e=$(mount -o ro "$1" "$2" 2>&1) && return 0; _e=$(mount -o ro,noload "$1" "$2" 2>&1) && return 0; _e=$(mount -t ext4 -o ro,noload "$1" "$2" 2>&1) && return 0; _e=$(mount -t ext2 -o ro "$1" "$2" 2>&1) && return 0; log "mount_ro $1 failed: $_e"; return 1; }
# The eMMC whole-disk node can appear before its partition nodes exist. Force a
# partition-table re-read, then (bulletproof) create any missing /dev/<disk>pN
# node straight from sysfs, which lists partitions as soon as the kernel parses
# the GPT — independent of udev/devtmpfs timing.
ensure_parts() { _disk="$1"; _base=$(basename "$_disk")
  partprobe "$_disk" 2>/dev/null; partx -a "$_disk" 2>/dev/null; blockdev --rereadpt "$_disk" 2>/dev/null
  udevadm trigger --subsystem-match=block --action=add 2>/dev/null; udevadm settle --timeout=5 2>/dev/null
  for _pd in /sys/block/"$_base"/"$_base"p*; do [ -d "$_pd" ] || continue; _pn="/dev/$(basename "$_pd")"; [ -e "$_pn" ] && continue; _mm=$(cat "$_pd/dev" 2>/dev/null); [ -n "$_mm" ] && mknod "$_pn" b "${_mm%:*}" "${_mm#*:}" 2>/dev/null && log "mknod $_pn ($_mm)"; done
}
find_emmc() { for d in /sys/block/mmcblk*; do b=$(basename "$d"); case "$b" in *boot*|*rpmb*) continue;; esac; sz=$(cat "$d/size" 2>/dev/null); [ "${sz:-0}" -gt 100000000 ] && { echo "/dev/$b"; return 0; }; done; return 1; }
# decompress a (possibly .gz/.xz) module to stdout
kocat() { case "$1" in *.gz) zcat "$1" 2>/dev/null;; *.xz) xzcat "$1" 2>/dev/null || xz -dc "$1" 2>/dev/null;; *) cat "$1" 2>/dev/null;; esac; }
# firmware-name tokens the driver may request (chip table + MODULE_FIRMWARE)
fwtokens() { kocat "$1" | grep -aoE 'brcmfmac[0-9a-z]+-(sdio|pcie)(\.[a-z0-9_]+)?|brcmfmac[0-9a-z]*\.(bin|txt|clm_blob)|brcm/brcmfmac[0-9a-z./-]+' | sort -u; }

n=0; while [ "$n" -lt 6 ]; do echo "" > "$CON"; echo "###### ICONIA WIFI99 DIAG (read-only) ######" > "$CON"; n=$((n+1)); done
say "=== baytrail-wifi99-diag.sh PID $$ ==="
log "USB kernel: $(uname -a 2>/dev/null)"

mkdir -p /run/udev; udevd --daemon 2>/dev/null || /lib/systemd/systemd-udevd --daemon 2>/dev/null
udevadm trigger --action=add 2>/dev/null; udevadm settle --timeout=10 2>/dev/null

# ---- bring up + mount the eMMC (identity detection; rebind renumbers) ----
DRV=/sys/bus/platform/drivers/sdhci-acpi; i=0; TARGET="$(find_emmc)"
while [ -z "$TARGET" ] && [ "$i" -lt 40 ]; do
  for base in 80860F14:00 80860F14:01; do [ -e "/sys/bus/platform/devices/$base" ] || continue; echo "$base" > "$DRV/unbind" 2>/dev/null; echo "$base" > "$DRV/bind" 2>/dev/null; done
  udevadm trigger --action=add 2>/dev/null; udevadm settle --timeout=5 2>/dev/null; sleep 2; i=$((i+1)); TARGET="$(find_emmc)"; say "ensure eMMC try $i: ${TARGET:-absent}"
done
[ -n "$TARGET" ] || finish "FATAL: no eMMC disk after $i tries — power-cycle & retry"
say "eMMC = $TARGET"

EROOTA="$(partdev "$TARGET" 3)"; ESTATE="$(partdev "$TARGET" 1)"
j=0; while [ ! -e "$EROOTA" ] && [ "$j" -lt 20 ]; do ensure_parts "$TARGET"; sleep 1; j=$((j+1)); say "wait eMMC parts try $j: p3 $([ -e "$EROOTA" ] && echo ok || echo absent)"; done
[ -e "$EROOTA" ] || finish "FATAL: eMMC partition nodes never appeared ($EROOTA) — tell me this line"
mkdir -p "$ROOTA_MNT" "$STATE_MNT"
mount_ro "$EROOTA" "$ROOTA_MNT" || finish "FATAL: cannot mount eMMC ROOT-A $EROOTA (see mount_ro line in log)"
mount_ro "$ESTATE" "$STATE_MNT" || finish "FATAL: cannot mount eMMC stateful $ESTATE (see mount_ro line in log)"
say "ROOT-A=$EROOTA (ro)  stateful=$ESTATE (ro)"

T99="$STATE_MNT/$STATE_SUB/$KVER99"                 # 6.6.99 tree on stateful
T76="$ROOTA_MNT/lib/modules/$KVER"                  # 6.6.76 tree (working) on rootfs
FWDIR="$ROOTA_MNT/lib/firmware/brcm"

hdr "TREE LAYOUT"
log "6.6.99 tree ($T99): $( [ -d "$T99" ] && echo present || echo MISSING )"
log "6.6.99 dir entry on rootfs /lib/modules/$KVER99: $(ls -ld "$ROOTA_MNT/lib/modules/$KVER99" 2>&1)"
log "  ^ if this is a symlink into stateful, brcmfmac may coldplug before stateful mounts (timing bug)"
log "6.6.76 tree ($T76): $( [ -d "$T76" ] && echo present || echo MISSING )"

KO99="$(find "$T99" -name 'brcmfmac.ko*' 2>/dev/null | head -1)"
KO76="$(find "$T76" -name 'brcmfmac.ko*' 2>/dev/null | head -1)"

hdr "6.6.99 brcmfmac — modinfo"
log "path: ${KO99:-NOT FOUND}"
[ -n "$KO99" ] && modinfo "$KO99" 2>&1 | grep -iE 'vermagic|^firmware|^depends|^alias.*(sdio|02D0|4324)|^filename' >> "$TRACE"

hdr "6.6.99 brcmfmac — firmware-name tokens (chip table + MODULE_FIRMWARE)"
[ -n "$KO99" ] && fwtokens "$KO99" >> "$TRACE"

hdr "6.6.76 brcmfmac (WORKING baseline) — firmware-name tokens"
log "path: ${KO76:-NOT FOUND}"
[ -n "$KO76" ] && fwtokens "$KO76" >> "$TRACE"
log "--- modinfo -F firmware (6.6.76) ---"
[ -n "$KO76" ] && modinfo -F firmware "$KO76" 2>&1 >> "$TRACE"

hdr "SDIO alias $SDIO_ALIAS (02D0:4324) in modules.alias"
log "6.6.99: $(grep -ic "$SDIO_ALIAS" "$T99/modules.alias" 2>/dev/null) match(es)"
grep -i "$SDIO_ALIAS" "$T99/modules.alias" 2>/dev/null >> "$TRACE"
log "6.6.76: $(grep -ic "$SDIO_ALIAS" "$T76/modules.alias" 2>/dev/null) match(es)  (should be >=1)"

hdr "6.6.99 brcmfmac dep chain — are all deps present in the tree?"
DEPLINE="$(grep -h 'brcmfmac\.ko' "$T99/modules.dep" 2>/dev/null | grep -v 'brcmfmac/.*:.*brcmfmac' | head -1)"
log "modules.dep line: ${DEPLINE:-NONE}"
if [ -n "$DEPLINE" ]; then
  DEPS="$(echo "$DEPLINE" | sed 's/^[^:]*://')"
  for d in $DEPS; do
    if [ -e "$T99/$d" ]; then log "  OK   $d"; else log "  MISS $d   <-- dependency file absent!"; fi
  done
fi

hdr "brcmfmac firmware STAGED on eMMC rootfs ($FWDIR)"
ls -la "$FWDIR" 2>&1 | grep -iE '43241|4324|brcmfmac' >> "$TRACE"
log "--- specifically b4 vs b5 (any form incl .xz) ---"
for name in brcmfmac43241b4-sdio.bin brcmfmac43241b5-sdio.bin brcmfmac43241b4-sdio.txt brcmfmac43241b5-sdio.txt brcmfmac43241b4-sdio.clm_blob brcmfmac43241b5-sdio.clm_blob; do
  hit="$(ls -1 "$FWDIR/$name" "$FWDIR/$name".xz 2>/dev/null)"
  log "  $name : ${hit:-ABSENT}"
done

hdr "VERDICT HINTS"
F99="$( [ -n "$KO99" ] && fwtokens "$KO99" | tr '\n' ' ')"
F76="$( [ -n "$KO76" ] && fwtokens "$KO76" | tr '\n' ' ')"
log "6.6.99 wants: $F99"
log "6.6.76 wants: $F76"
if [ "$F99" = "$F76" ]; then
  log ">> 6.6.99 and 6.6.76 reference the SAME firmware names => NOT a missing-blob problem."
  log ">> Root cause is almost certainly LOAD TIMING (6.6.99 tree symlinked to stateful,"
  log ">> brcmfmac coldplugs before stateful mounts). Fix = udevadm re-coldplug hook after"
  log ">> stateful, or place the 6.6.99 brcmfmac (+deps) as real files on the rootfs."
else
  log ">> 6.6.99 references DIFFERENT firmware names than the working 6.6.76 driver."
  log ">> Compare the two lists above; stage any blob 6.6.99 wants that is ABSENT on the rootfs."
fi

sync
umount "$STATE_MNT" 2>/dev/null
umount "$ROOTA_MNT" 2>/dev/null
finish "*** WIFI99 DIAG COMPLETE — full report in $TRACE on the USB ***"
