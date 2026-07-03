#!/bin/sh
# Iconia W4-820 — install an SSH server onto the eMMC rootfs (PID 1, off USB) so we
# can debug the running FydeOS live over wifi (dead keyboard -> no local shell).
# The rootfs boots ro, so we PRE-GENERATE host keys into eMMC /etc/ssh and place
# authorized_keys offline; sshd runs from an upstart job with -o overrides (no need
# to edit the stock sshd_config). shill keeps wifi up (join once at OOBE via touch).
# Does NOT change eMMC init= — the eMMC boots normally to OOBE with sshd running.
export PATH=/usr/sbin:/usr/bin:/sbin:/bin
CON=/dev/tty1
TRACE=/iconia-emmc-sshsetup.log
EROOTA_MNT=/mnt/e-root
PUBKEY="ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIAqCHXyyzv9BwTfH03fS7efejEMir3U2y1Gq8TlvA2o/ iconia-debug"

mount -t proc proc /proc 2>/dev/null
mount -t sysfs sys /sys 2>/dev/null
mount -t devtmpfs dev /dev 2>/dev/null
mount -t tmpfs run /run 2>/dev/null
mount -o remount,rw / 2>/dev/null || true

say() { _m="[$(date -u '+%H:%M:%S' 2>/dev/null)] $*"; echo "ICONIA $_m" > "$CON" 2>/dev/null||true; echo "$_m" >> "$TRACE" 2>/dev/null||true; sync 2>/dev/null||true; }
finish() { say "$1"; sync; sleep "${2:-10}"; poweroff -f 2>/dev/null; echo o > /proc/sysrq-trigger 2>/dev/null; while true; do sleep 60; done; }
partdev() { case "$1" in *[0-9]) echo "$1p$2";; *) echo "$1$2";; esac; }
find_emmc() { for d in /sys/block/mmcblk*; do b=$(basename "$d"); case "$b" in *boot*|*rpmb*) continue;; esac; sz=$(cat "$d/size" 2>/dev/null); [ "${sz:-0}" -gt 100000000 ] && { echo "/dev/$b"; return 0; }; done; return 1; }

n=0; while [ "$n" -lt 6 ]; do echo "" > "$CON"; echo "#### ICONIA eMMC SSH SETUP ####" > "$CON"; n=$((n+1)); done
say "=== iconia-emmc-sshsetup.sh PID $$ ==="
mkdir -p /run/udev; udevd --daemon 2>/dev/null || /lib/systemd/systemd-udevd --daemon 2>/dev/null
udevadm trigger --action=add 2>/dev/null; udevadm settle --timeout=10 2>/dev/null

DRV=/sys/bus/platform/drivers/sdhci-acpi; i=0; TARGET="$(find_emmc)"
while [ -z "$TARGET" ] && [ "$i" -lt 40 ]; do
  for base in 80860F14:00 80860F14:01; do [ -e "/sys/bus/platform/devices/$base" ] || continue; echo "$base" > "$DRV/unbind" 2>/dev/null; echo "$base" > "$DRV/bind" 2>/dev/null; done
  udevadm trigger --action=add 2>/dev/null; udevadm settle --timeout=5 2>/dev/null; sleep 2; i=$((i+1)); TARGET="$(find_emmc)"; say "ensure eMMC try $i: ${TARGET:-absent}"
done
[ -n "$TARGET" ] || finish "FATAL: no eMMC after $i tries — power-cycle & retry" 20
say "eMMC = $TARGET"

EROOTA="$(partdev "$TARGET" 3)"; mkdir -p "$EROOTA_MNT"
mount "$EROOTA" "$EROOTA_MNT" 2>/dev/null || finish "FATAL: cannot mount eMMC ROOT-A $EROOTA" 20
mount -o remount,rw "$EROOTA_MNT" 2>/dev/null
R="$EROOTA_MNT"

# --- host keys (pre-generate; rootfs is ro at runtime) ---
mkdir -p "$R/etc/ssh"
[ -f "$R/etc/ssh/ssh_host_ed25519_key" ] || ssh-keygen -q -t ed25519 -N '' -f "$R/etc/ssh/ssh_host_ed25519_key" 2>>"$TRACE"
[ -f "$R/etc/ssh/ssh_host_rsa_key" ]     || ssh-keygen -q -t rsa -b 2048 -N '' -f "$R/etc/ssh/ssh_host_rsa_key" 2>>"$TRACE"
say "host keys: $(ls "$R/etc/ssh"/ssh_host_*_key 2>/dev/null | tr '\n' ' ')"

# --- privsep user (modern OpenSSH refuses to start without it) ---
grep -q '^sshd:' "$R/etc/passwd" 2>/dev/null || printf 'sshd:x:33:33:sshd:/run/sshd:/bin/false\n' >> "$R/etc/passwd"
grep -q '^sshd:' "$R/etc/group"  2>/dev/null || printf 'sshd:x:33:\n' >> "$R/etc/group"
say "sshd user: $(grep '^sshd:' "$R/etc/passwd")"

# --- authorized_keys for root ---
mkdir -p "$R/root/.ssh"; chmod 700 "$R/root/.ssh"
printf '%s\n' "$PUBKEY" > "$R/root/.ssh/authorized_keys"
chmod 600 "$R/root/.ssh/authorized_keys"; chown 0:0 "$R/root/.ssh" "$R/root/.ssh/authorized_keys" 2>/dev/null
say "authorized_keys installed"

# --- upstart job to run sshd with safe -o overrides ---
cat > "$R/etc/init/iconia-sshd.conf" <<'EOF'
# Iconia debug SSH (key-only root login). boot-services is an early, reliable
# ChromeOS milestone; sshd binds even before wifi is up. Opens the inbound
# firewall (ChromeOS drops inbound by default) then runs sshd with -o overrides.
start on started boot-services
respawn
respawn limit 20 120
pre-start script
  mkdir -p /run/sshd
  iptables  -I INPUT -p tcp --dport 22 -j ACCEPT || true
  ip6tables -I INPUT -p tcp --dport 22 -j ACCEPT || true
end script
exec /usr/sbin/sshd -D \
  -o PermitRootLogin=prohibit-password \
  -o PubkeyAuthentication=yes \
  -o PasswordAuthentication=no \
  -o KbdInteractiveAuthentication=no \
  -o UsePAM=no \
  -o AuthorizedKeysFile=/root/.ssh/authorized_keys \
  -o PidFile=/run/sshd.pid
EOF
say "upstart job /etc/init/iconia-sshd.conf written"
sync
umount "$EROOTA_MNT" 2>/dev/null
finish "=== SSH SETUP DONE — boot eMMC, join wifi at OOBE (touch), then SSH root@<tablet-ip> ===" 12
