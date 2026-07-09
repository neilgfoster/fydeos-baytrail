#!/bin/sh
# Iconia W4-820 — FIX WiFi-on-6.6.99 by making the 6.6.99 module tree REAL on the
# rootfs (PID 1, init= wrapper). Writes to the eMMC rootfs.
#
# ROOT CAUSE (proven by iconia-wifi99-diag / iconia-esp99-diag): /lib/modules/
# 6.6.99-* on the rootfs is a SYMLINK into stateful, so brcmfmac coldplugs at early
# boot BEFORE stateful mounts -> dangling -> no wlan. (NOT firmware: 6.6.99 & 6.6.76
# request identical brcm blobs; b4 present; SDIO alias + deps present.)
#
# The rootfs is 2.7G / ~100% full and holds only ONE module tree; stateful holds
# BOTH (6.6.76 + 6.6.99). So SWAP:
#   1. delete the real 6.6.76 tree on rootfs  -> per-version symlink into stateful
#      (only AFTER verifying the stateful 6.6.76 copy is complete)
#   2. copy the stateful 6.6.99 tree -> rootfs as REAL files (loads early like 6.76)
#   3. depmod + verify brcmfmac SDIO alias survives
# After this, boot the "FydeOS R144 TEST (6.6.99)" grub entry -> WiFi comes up early.
# 6.6.76 then loses early WiFi (still boots as a fallback); revert with
# iconia-modules-restore.sh. Progress -> /dev/kmsg (earlycon) AND USB log.
export PATH=/usr/sbin:/usr/bin:/sbin:/bin
CON=/dev/tty1
K76=6.6.76-gabcfb16364e1; K99=6.6.99-g7232af57f054
RM=/mnt/er; SM=/mnt/es; T=/iconia-wifi99-fix.log; AL=v02D0d4324
SUB=unencrypted/lib-modules

mount -t proc proc /proc 2>/dev/null; mount -t sysfs sys /sys 2>/dev/null
mount -t devtmpfs dev /dev 2>/dev/null; mount -t tmpfs run /run 2>/dev/null
mount -o remount,rw / 2>/dev/null; : > "$T" 2>/dev/null || T=/tmp/fix.log

say() { _m="[$(date -u '+%H:%M:%S' 2>/dev/null)] $*"; echo "ICONIA $_m" > "$CON" 2>/dev/null||true; echo "ICONIA: $*" > /dev/kmsg 2>/dev/null||true; echo "$_m" >> "$T"; sync 2>/dev/null||true; }
log() { echo "$*" >> "$T"; }
finish() { echo "ICONIA: #### WIFI99 FIX HALT ####" > /dev/kmsg 2>/dev/null||true; echo "#### WIFI99 FIX HALT ####" > "$CON"; say "$1"; say "log on USB: $T -- power off ~10s, remove USB, boot R144 entry"; while :; do sleep 3600; done; }
PD() { case "$1" in *[0-9]) echo "$1p$2";; *) echo "$1$2";; esac; }
mount_rw() { _e=$(mount "$1" "$2" 2>&1) && return 0; _e=$(mount -o rw,noload "$1" "$2" 2>&1) && return 0; log "mount_rw $1 failed: $_e"; return 1; }
EMMC() { for d in /sys/block/mmcblk*; do b=$(basename "$d"); case "$b" in *boot*|*rpmb*) continue;; esac; sz=$(cat "$d/size" 2>/dev/null); [ "${sz:-0}" -gt 100000000 ] && { echo "/dev/$b"; return; }; done; }
ensure_parts() { _disk="$1"; _base=$(basename "$_disk"); partprobe "$_disk" 2>/dev/null; partx -a "$_disk" 2>/dev/null; blockdev --rereadpt "$_disk" 2>/dev/null; udevadm trigger --subsystem-match=block --action=add 2>/dev/null; udevadm settle --timeout=5 2>/dev/null; for _pd in /sys/block/"$_base"/"$_base"p*; do [ -d "$_pd" ] || continue; _pn="/dev/$(basename "$_pd")"; [ -e "$_pn" ] && continue; _mm=$(cat "$_pd/dev" 2>/dev/null); [ -n "$_mm" ] && mknod "$_pn" b "${_mm%:*}" "${_mm#*:}" 2>/dev/null; done; }
alias_ok() { grep -qi "$AL" "$1/modules.alias" 2>/dev/null; }

n=0; while [ $n -lt 6 ]; do echo "###### ICONIA WIFI99 FIX (writes rootfs) ######" > "$CON"; echo "ICONIA: WIFI99 FIX start" > /dev/kmsg 2>/dev/null; n=$((n+1)); done
say "start PID $$"; log "USB: $(uname -a)"
mkdir -p /run/udev; udevd --daemon 2>/dev/null || /lib/systemd/systemd-udevd --daemon 2>/dev/null
udevadm trigger --action=add 2>/dev/null; udevadm settle --timeout=10 2>/dev/null

TG=$(EMMC); [ -n "$TG" ] || finish "FATAL no eMMC"
say "eMMC=$TG"
RA=$(PD "$TG" 3); ST=$(PD "$TG" 1)
j=0; while [ ! -e "$RA" ] && [ $j -lt 20 ]; do ensure_parts "$TG"; sleep 1; j=$((j+1)); say "wait parts $j"; done
mkdir -p "$RM" "$SM"
mount_rw "$RA" "$RM" || finish "FATAL mount ROOT-A $RA rw"
mount_rw "$ST" "$SM" || finish "FATAL mount stateful $ST rw"
say "mounted ROOT-A + stateful (rw)"

LM="$RM/lib/modules"
S76="$SM/$SUB/$K76"        # stateful 6.6.76 (symlink target / safety copy)
S99="$SM/$SUB/$K99"        # stateful 6.6.99 (source to copy real)

# --- preconditions ---
[ -d "$S99" ] && [ -e "$S99/modules.dep" ] || finish "FATAL: stateful 6.6.99 tree incomplete at $S99"
alias_ok "$S99" || finish "FATAL: stateful 6.6.99 modules.alias lacks $AL — aborting (would break wifi)"
say "stateful 6.6.99 verified (modules.dep + $AL alias present)"

# already fixed? (idempotent re-run)
if [ -d "$LM/$K99" ] && [ ! -L "$LM/$K99" ] && [ -e "$LM/$K99/kernel/drivers/net/wireless/broadcom/brcm80211/brcmfmac/brcmfmac.ko.gz" ]; then
  say "6.6.99 tree already REAL on rootfs — nothing to do"
  alias_ok "$LM/$K99" && finish "ALREADY FIXED — 6.6.99 real on rootfs, alias OK. Boot R144." || say "WARN: real tree present but alias missing; will re-copy"
fi

# --- step 1: relocate 6.6.76 -> per-version symlink into stateful (frees ~200M) ---
# verify the stateful 6.6.76 copy is complete BEFORE deleting the rootfs one.
if [ -d "$S76" ] && [ -e "$S76/modules.dep" ]; then
  say "stateful 6.6.76 copy verified; freeing rootfs 6.6.76 tree"
else
  say "stateful 6.6.76 missing/incomplete — copying rootfs 6.6.76 -> stateful first"
  [ -d "$LM/$K76" ] && [ ! -L "$LM/$K76" ] || finish "FATAL: no valid rootfs 6.6.76 to preserve and none on stateful"
  mkdir -p "$SM/$SUB"; cp -a "$LM/$K76" "$SM/$SUB/" 2>>"$T" || finish "FATAL: preserving 6.6.76 to stateful failed"
  sync
fi
if [ -L "$LM/$K76" ]; then say "6.6.76 already a symlink"; else rm -rf "$LM/$K76" 2>>"$T"; fi
ln -sfn "/mnt/stateful_partition/$SUB/$K76" "$LM/$K76"
sync
say "6.6.76 -> $(ls -ld "$LM/$K76" 2>&1 | sed 's#.*/lib/modules/##'); ROOT-A free now: $(df -h "$RM" 2>/dev/null | awk 'END{print $4}')"

# --- step 2: copy stateful 6.6.99 -> rootfs as REAL files ---
if [ -L "$LM/$K99" ]; then rm -f "$LM/$K99"; fi
rm -rf "$LM/$K99" 2>/dev/null
say "copying 6.6.99 tree (~149M) stateful -> rootfs real ..."
cp -a "$S99" "$LM/" 2>>"$T"; RC=$?
sync
say "cp exit=$RC ; ROOT-A free after: $(df -h "$RM" 2>/dev/null | awk 'END{print $4}')"
[ "$RC" = 0 ] || finish "FATAL: copy failed (RC=$RC) — likely OUT OF SPACE. Tell me this line."

# --- step 3: depmod + verify ---
say "depmod $K99 on rootfs ..."
depmod -b "$RM" "$K99" 2>>"$T"
KO="$LM/$K99/kernel/drivers/net/wireless/broadcom/brcm80211/brcmfmac/brcmfmac.ko.gz"
REAL=0; [ -e "$KO" ] && [ ! -L "$LM/$K99" ] && REAL=1
ALOK=0; alias_ok "$LM/$K99" && ALOK=1
DEP=$(grep -c brcmfmac "$LM/$K99/modules.dep" 2>/dev/null)
say "verify: brcmfmac.ko real=$REAL  alias $AL=$ALOK  modules.dep brcmfmac=$DEP (all should be >0)"
log "final /lib/modules:"; ls -la "$LM" >> "$T" 2>&1

sync
umount "$SM" 2>/dev/null
umount "$RM" 2>/dev/null

if [ "$REAL" = 1 ] && [ "$ALOK" = 1 ] && [ "${DEP:-0}" -gt 0 ]; then
  finish "*** WIFI99 FIX OK — 6.6.99 modules REAL on rootfs, brcmfmac indexed. Remove USB, boot the 'FydeOS R144 TEST (6.6.99)' grub entry — WiFi should come up. ***"
else
  finish "!!! FIX INCOMPLETE (real=$REAL alias=$ALOK dep=$DEP) — tell me this line BEFORE booting; revert available via iconia-modules-restore.sh !!!"
fi
