#!/bin/sh
# Iconia W4-820 — read-only diagnostic dump (PID 1, run from USB utility boot).
#
# The eMMC still bootloops even after iconia-esp-restore.sh restored vmlinuz.A
# from vmlinuz.A.bak-bt. Before doing anything else destructive, pull the actual
# state off the eMMC ESP (current vmlinuz.A hash, the restore script's own trace
# log, and any captured pstore crash data) onto the USB's own STATE partition so
# it can be read from the crosh host after removing the USB — no more blind
# eMMC boot cycles.
export PATH=/usr/sbin:/usr/bin:/sbin:/bin
CON=/dev/tty1
EESP_MNT=/mnt/iconia-eesp
USTATE_MNT=/mnt/iconia-ustate
OUT=/mnt/iconia-ustate/iconia-diag-out
TRACE=/mnt/iconia-ustate/iconia-diag-out/trace.log

mount -t proc proc /proc 2>/dev/null
mount -t sysfs sys /sys 2>/dev/null
mount -t devtmpfs dev /dev 2>/dev/null
mount -t tmpfs run /run 2>/dev/null

say() { _m="[$(date -u '+%H:%M:%S' 2>/dev/null)] $*"; echo "ICONIA $_m" > "$CON" 2>/dev/null||true; echo "$_m" >> "$TRACE" 2>/dev/null||true; echo "ICONIA: $*" > /dev/kmsg 2>/dev/null||true; sync 2>/dev/null||true; }
# On fatal error: halt with the message on screen instead of racing to power off
# — every prior run scrolled/powered off too fast to read. Power off manually.
finish() { echo "" > "$CON"; echo "#### ICONIA FATAL ####" > "$CON"; say "$1"; say "=== HALTED — read this, then hold power ~10s to shut down ==="; while true; do sleep 3600; done; }
partdev() { case "$1" in *[0-9]) echo "$1p$2";; *) echo "$1$2";; esac; }
find_emmc() { for d in /sys/block/mmcblk*; do b=$(basename "$d"); case "$b" in *boot*|*rpmb*) continue;; esac; sz=$(cat "$d/size" 2>/dev/null); [ "${sz:-0}" -gt 100000000 ] && { echo "/dev/$b"; return 0; }; done; return 1; }
# USB stick is ~7.5GB -> ~15.7M 512-byte sectors. Don't rely on `rootdev` this
# early (it returned garbage/empty on the previous run before udev fully
# settled, the mount silently failed, and everything after kept "succeeding"
# against a directory that only existed on ephemeral RAM-root — nothing
# persisted to real storage even though the on-screen text looked normal).
find_usb() { for d in /sys/block/sd*; do b=$(basename "$d"); sz=$(cat "$d/size" 2>/dev/null); [ "${sz:-0}" -gt 5000000 ] && [ "${sz:-0}" -lt 20000000 ] && { echo "/dev/$b"; return 0; }; done; return 1; }

n=0; while [ "$n" -lt 6 ]; do echo "" > "$CON"; echo "#### ICONIA ESP DIAG (read-only) ####" > "$CON"; n=$((n+1)); done

# Mount USB STATE and point the trace log there FIRST, before anything else can
# fail — this is the fix for the previous run producing no output at all: the
# old script only logged to the ephemeral USB rootfs (gone on poweroff) until
# far later in the script, so any early failure left nothing to inspect.
mkdir -p /run/udev; udevd --daemon 2>/dev/null || /lib/systemd/systemd-udevd --daemon 2>/dev/null
udevadm trigger --action=add 2>/dev/null; udevadm settle --timeout=10 2>/dev/null
i=0; USB_DISK="$(find_usb)"
while [ -z "$USB_DISK" ] && [ "$i" -lt 20 ]; do
  udevadm trigger --action=add 2>/dev/null; udevadm settle --timeout=5 2>/dev/null; sleep 1; i=$((i+1)); USB_DISK="$(find_usb)"
done
[ -n "$USB_DISK" ] || finish "FATAL: no USB disk found after $i tries — cannot save any output at all" 20
USTATE="$(partdev "$USB_DISK" 1)"
mkdir -p "$USTATE_MNT"
j=0
until mount "$USTATE" "$USTATE_MNT" 2>/dev/null; do
  j=$((j+1)); [ "$j" -ge 15 ] && finish "FATAL: could not mount USTATE=$USTATE after $j tries — cannot save any output at all" 20
  sleep 1
done
mkdir -p "$OUT"
say "=== iconia-esp-diag.sh PID $$ === USB_DISK=$USB_DISK USTATE=$USTATE (mount took $j tries)"
touch "$OUT/.write-test" 2>/dev/null && say "USTATE is WRITABLE, confirmed" || say "WARNING: USTATE mounted but NOT writable"

DRV=/sys/bus/platform/drivers/sdhci-acpi; i=0; TARGET="$(find_emmc)"
while [ -z "$TARGET" ] && [ "$i" -lt 40 ]; do
  for base in 80860F14:00 80860F14:01; do [ -e "/sys/bus/platform/devices/$base" ] || continue; echo "$base" > "$DRV/unbind" 2>/dev/null; echo "$base" > "$DRV/bind" 2>/dev/null; done
  udevadm trigger --action=add 2>/dev/null; udevadm settle --timeout=5 2>/dev/null; sleep 2; i=$((i+1)); TARGET="$(find_emmc)"; say "ensure eMMC try $i: ${TARGET:-absent}"
done
[ -n "$TARGET" ] || finish "FATAL: no eMMC after $i tries — power-cycle & retry" 20
say "eMMC = $TARGET"

mkdir -p "$EESP_MNT"
mount -o ro "$(partdev "$TARGET" 12)" "$EESP_MNT" 2>/dev/null || finish "FATAL: cannot mount eMMC ESP" 20

say "collecting eMMC ESP state ..."
{
  echo "=== ls -la syslinux ==="; ls -la "$EESP_MNT/syslinux/" 2>&1
  echo "=== sha256sum vmlinuz.A + backups ==="; sha256sum "$EESP_MNT"/syslinux/vmlinuz.A* 2>&1
  echo "=== usb.A.cfg / root.A.cfg (in case boot config also changed) ==="; cat "$EESP_MNT/syslinux/root.A.cfg" 2>&1
} > "$OUT/esp-state.txt" 2>&1

[ -f "$EESP_MNT/iconia-esp-restore.log" ] && cp -a "$EESP_MNT/iconia-esp-restore.log" "$OUT/" 2>/dev/null
[ -d "$EESP_MNT/syslinux/pstore-k12-crash" ] && cp -a "$EESP_MNT/syslinux/pstore-k12-crash" "$OUT/" 2>/dev/null

dmesg > "$OUT/dmesg-usb-boot.txt" 2>&1

say "diag output saved to USB STATE:/iconia-diag-out/"

sync
umount "$EESP_MNT" 2>/dev/null
sync
umount "$USTATE_MNT" 2>/dev/null

# Do NOT auto-poweroff — hold a static summary on screen indefinitely so it can
# actually be read/photographed (scrolling text + fast poweroff made every prior
# run undiagnosable). Power off manually (hold power ~10s) once you've read it.
echo "" > "$CON"; echo "#### ICONIA DIAG DONE — HOLD POWER ~10s TO SHUT DOWN ####" > "$CON"
echo "USB_DISK=$USB_DISK  USTATE=$USTATE  eMMC=$TARGET" > "$CON"
cat "$OUT/esp-state.txt" > "$CON" 2>/dev/null
say "=== halted for manual read — power off when done ==="
while true; do sleep 3600; done
