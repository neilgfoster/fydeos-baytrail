#!/bin/bash
# thinkpad-ssh.sh — re-orient + health-check for the ThinkPad 10 20C1 remote channel.
# Run this FIRST in any session that touches the ThinkPad. It verifies the live SSH
# channel, relocates the tablet if DHCP moved its IP, and reprints the NEVER-BREAK-SSH
# rules so context is never lost to a new session / compact / clear.
#
#   Usage: scripts/thinkpad-ssh.sh          # check + reprint rules
#          scripts/thinkpad-ssh.sh --find   # force LAN rescan by SSH key
set -uo pipefail

ALIAS=thinkpad10
KEY=~/.ssh/thinkpad10
FINDER=~/.ssh/find-thinkpad.sh
EXPECT_HOST=Lenovo-PC

cat <<'RULES'
================================================================================
  ThinkPad 10 20C1 — NEVER BREAK SSH   (read before ANY action on this device)
--------------------------------------------------------------------------------
  * Windows sshd is remote channel #1 — the ONLY way back into this device
    (USB port is dead; SD is not firmware-bootable). Losing it = losing the box.
  * Do NOT run anything that can drop it WITHOUT a proven parallel channel first:
      - no disabling/removing sshd, its firewall rule, or the admin key
      - no wiping/repartitioning the eMMC, no OS install, no boot-order change,
        no GRUB/bootloader write, no network/adapter change
      until a SECOND SSH channel (in Linux/recovery/FydeOS) is PROVEN in parallel.
  * PROVE-NEW-BEFORE-DEPRECATING-OLD. Always overlap channels; never hand off blind.
  * This rule stays in force for ALL ThinkPad10 work until another boot+SSH method
    is proven. See CLAUDE.md and memory [[thinkpad10-20c1-boot-blocked]].
================================================================================
RULES

echo
echo "== Verifying live channel (ssh $ALIAS) =="
hn=$(ssh -o ConnectTimeout=6 "$ALIAS" "hostname" 2>/dev/null | tr -d '\r')
if [ "${1:-}" = "--find" ] || [ "$hn" != "$EXPECT_HOST" ]; then
  echo "!! Direct alias failed or forced --find; scanning LAN by SSH key..."
  [ -x "$FINDER" ] && "$FINDER"
  echo "   (if found at a new IP, update HostName in ~/.ssh/config for '$ALIAS')"
else
  ip=$(ssh -G "$ALIAS" 2>/dev/null | awk '/^hostname /{print $2}')
  echo "OK: reachable — hostname=$hn at $ip"
  echo
  echo "== sshd status on device =="
  ssh "$ALIAS" "sc query sshd | findstr STATE & sc qc sshd | findstr START_TYPE" 2>/dev/null \
    | tr -d '\r' | sed 's/^/   /' || true
fi
