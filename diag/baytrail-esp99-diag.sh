#!/bin/sh
# Iconia W4-820 — pre-fix probe for WiFi-on-6.6.99 (PID 1, init= wrapper). READ-ONLY.
#
# The wifi99 diag proved the cause is LOAD TIMING: /lib/modules/6.6.99-* on the
# rootfs is a symlink into stateful, so brcmfmac coldplugs (early) before stateful
# mounts -> no wlan. Fix = make the 6.6.99 tree REAL files on the rootfs. Two
# strategies depending on space:
#   (A) BOTH trees fit real on rootfs  -> keep 6.6.76 real too (both kernels get
#       working wifi; 6.6.76 stays a safe SSH fallback). BEST.
#   (B) only one fits -> swap: 6.6.99 real, 6.6.76 -> per-version symlink.
# This probe measures rootfs free space + both tree sizes to choose A vs B, and
# dumps the eMMC ESP boot config so the R144 kernel re-stage (S16 wiped it) is
# built from the REAL current cmdline, not guessed. Nothing is modified.
# Progress is echoed to /dev/kmsg (visible via earlycon=efifb) AND logged to USB.
export PATH=/usr/sbin:/usr/bin:/sbin:/bin
CON=/dev/tty1
K76=6.6.76-gabcfb16364e1; K99=6.6.99-g7232af57f054
RM=/mnt/er; SM=/mnt/es; EM=/mnt/ee; T=/baytrail-esp99-diag.log

mount -t proc proc /proc 2>/dev/null; mount -t sysfs sys /sys 2>/dev/null
mount -t devtmpfs dev /dev 2>/dev/null; mount -t tmpfs run /run 2>/dev/null
mount -o remount,rw / 2>/dev/null; : > "$T" 2>/dev/null || T=/tmp/d.log

say() { _m="[$(date -u '+%H:%M:%S' 2>/dev/null)] $*"; echo "ICONIA $_m" > "$CON" 2>/dev/null||true; echo "ICONIA: $*" > /dev/kmsg 2>/dev/null||true; echo "$_m" >> "$T"; sync 2>/dev/null||true; }
log() { echo "$*" >> "$T"; }
hdr() { log ""; log "======== $* ========"; }
finish() { echo "ICONIA: #### ESP99 DIAG HALT ####" > /dev/kmsg 2>/dev/null||true; echo "#### ESP99 DIAG HALT ####" > "$CON"; say "$1"; say "log on USB: $T -- power off ~10s, read on laptop"; while :; do sleep 3600; done; }
PD() { case "$1" in *[0-9]) echo "$1p$2";; *) echo "$1$2";; esac; }
mount_ro() { _e=$(mount -o ro "$1" "$2" 2>&1) && return 0; _e=$(mount -o ro,noload "$1" "$2" 2>&1) && return 0; _e=$(mount -t vfat -o ro "$1" "$2" 2>&1) && return 0; _e=$(mount -t ext2 -o ro "$1" "$2" 2>&1) && return 0; log "mount_ro $1 failed: $_e"; return 1; }
EMMC() { for d in /sys/block/mmcblk*; do b=$(basename "$d"); case "$b" in *boot*|*rpmb*) continue;; esac; sz=$(cat "$d/size" 2>/dev/null); [ "${sz:-0}" -gt 100000000 ] && { echo "/dev/$b"; return; }; done; }
ensure_parts() { _disk="$1"; _base=$(basename "$_disk"); partprobe "$_disk" 2>/dev/null; partx -a "$_disk" 2>/dev/null; blockdev --rereadpt "$_disk" 2>/dev/null; udevadm trigger --subsystem-match=block --action=add 2>/dev/null; udevadm settle --timeout=5 2>/dev/null; for _pd in /sys/block/"$_base"/"$_base"p*; do [ -d "$_pd" ] || continue; _pn="/dev/$(basename "$_pd")"; [ -e "$_pn" ] && continue; _mm=$(cat "$_pd/dev" 2>/dev/null); [ -n "$_mm" ] && mknod "$_pn" b "${_mm%:*}" "${_mm#*:}" 2>/dev/null; done; }

n=0; while [ $n -lt 6 ]; do echo "###### ICONIA ESP99 DIAG (read-only) ######" > "$CON"; echo "ICONIA: ESP99 DIAG start" > /dev/kmsg 2>/dev/null; n=$((n+1)); done
say "start PID $$"; log "USB: $(uname -a)"
mkdir -p /run/udev; udevd --daemon 2>/dev/null || /lib/systemd/systemd-udevd --daemon 2>/dev/null
udevadm trigger --action=add 2>/dev/null; udevadm settle --timeout=10 2>/dev/null

TG=$(EMMC); [ -n "$TG" ] || finish "FATAL no eMMC"
say "eMMC=$TG"
RA=$(PD "$TG" 3); ST=$(PD "$TG" 1); ES=$(PD "$TG" 12)
j=0; while [ ! -e "$RA" ] && [ $j -lt 20 ]; do ensure_parts "$TG"; sleep 1; j=$((j+1)); say "wait parts $j"; done
mkdir -p "$RM" "$SM" "$EM"
mount_ro "$RA" "$RM" || finish "FATAL mount ROOT-A $RA"
mount_ro "$ST" "$SM" || finish "FATAL mount stateful $ST"
mount_ro "$ES" "$EM" || say "WARN: cannot mount ESP $ES (will still report modules/space)"
say "mounted ROOT-A + stateful + ESP(ro)"

hdr "ROOTFS SPACE (the A-vs-B decision)"
df -h "$RM" >> "$T" 2>&1
FREEK=$(df -k "$RM" 2>/dev/null | awk 'END{print $4}'); log "ROOT-A free KB: ${FREEK:-?}"
say "ROOT-A free: $(df -h "$RM" 2>/dev/null | awk 'END{print $4}')"

hdr "MODULE TREE SIZES"
LM="$RM/lib/modules"
log "rootfs /lib/modules entries:"; ls -la "$LM" >> "$T" 2>&1
S76=$(du -sk "$LM/$K76" 2>/dev/null | cut -f1); log "6.6.76 tree (rootfs, real): ${S76:-?} KB"
T99S="$SM/unencrypted/lib-modules/$K99"; S99=$(du -sk "$T99S" 2>/dev/null | cut -f1); log "6.6.99 tree (stateful): ${S99:-?} KB"
log "stateful lib-modules trees present:"; ls -la "$SM/unencrypted/lib-modules" >> "$T" 2>&1
say "6.76=${S76:-?}KB 6.99=${S99:-?}KB free=${FREEK:-?}KB"
if [ -n "$S99" ] && [ -n "$FREEK" ]; then
  if [ "$S99" -lt "$FREEK" ]; then say "VERDICT: 6.6.99 tree FITS alongside 6.6.76 -> strategy A (keep both real)"; log ">> STRATEGY A: 6.6.99 ($S99 KB) < free ($FREEK KB); add it real, keep 6.6.76."; \
  else say "VERDICT: not enough free -> strategy B (swap)"; log ">> STRATEGY B: 6.6.99 ($S99 KB) >= free ($FREEK KB); must relocate 6.6.76 to stateful symlink first."; fi
fi

hdr "eMMC ESP ($ES) — boot config"
if mountpoint -q "$EM" 2>/dev/null || [ -e "$EM/boot/grub/grub.cfg" ]; then
  log "ESP /boot/grub/grub.cfg:"; sed -n '1,80p' "$EM/boot/grub/grub.cfg" >> "$T" 2>&1
  log ""; log "ESP /syslinux (kernels):"; ls -la "$EM/syslinux" >> "$T" 2>&1
  log ""; log "ESP /efi/boot:"; ls -la "$EM/efi/boot" >> "$T" 2>&1
else
  log "ESP not mounted / grub.cfg not found — check $ES manually"
fi

sync; umount "$EM" 2>/dev/null; umount "$SM" 2>/dev/null; umount "$RM" 2>/dev/null
finish "ESP99 DIAG DONE -- report in $T"
