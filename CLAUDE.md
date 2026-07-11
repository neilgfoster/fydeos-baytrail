# fydeos-baytrail — repo guide

Bay Trail FydeOS bring-up framework. Active board: **Lenovo ThinkPad 10 20C1**.
Read `PROGRESS.md` for where we are and what's next.

---

# 🚨 NEVER BREAK SSH — ThinkPad 10 20C1 (HARD RULE, always in force)

**This rule is authoritative and overrides convenience, speed, or any plan step.**
It applies to *every* session, and remains in force for **all** ThinkPad 10 work
**until a second, independent boot+SSH method has been PROVEN** (and recorded here as
proven). Do not infer around it; do not assume a later step made it safe.

**Why:** The tablet's USB port is dead and its SD card is not firmware-bootable. The
Windows `sshd` service is **channel #1 — the only way back into the device.** If it is
lost, we cannot get remote access back without physical media we cannot boot. Losing
SSH = losing the box.

### Before doing ANYTHING on the ThinkPad, run the re-orient command:

```
scripts/thinkpad-ssh.sh
```

It verifies the live channel, relocates the tablet if DHCP moved its IP
(`~/.ssh/find-thinkpad.sh`), and reprints these rules. Run it at the start of any
ThinkPad session and any time context may have been lost (new session / compact / clear).

### The rules

1. **Never take an action that can drop SSH without a PROVEN parallel channel first.**
   That includes, non-exhaustively: disabling/removing `sshd`, its firewall rule, or the
   admin authorized key; wiping/repartitioning the eMMC; any OS install; boot-order or
   firmware boot-entry changes; writing/replacing a bootloader (GRUB); changing the
   network adapter / WiFi config.
2. **Prove-new-before-deprecating-old.** Any replacement access method (SSH in a
   Linux/recovery/FydeOS environment) must be brought up and **verified working IN
   PARALLEL** with Windows `sshd` before Windows `sshd` is retired or the disk it lives
   on is touched. Always overlap channels; never hand off blind.
3. **When unsure whether a step endangers SSH, STOP and treat it as if it does.**

### Access facts (channel #1)

- Connect: `ssh thinkpad10` (passwordless admin; key `~/.ssh/thinkpad10`, alias in
  `~/.ssh/config`). Device: Win 8.1, host `Lenovo-PC`, acct `myPC` (temp LAN password
  fallback is in local memory `[[thinkpad10-20c1-boot-blocked]]`, not stored in this repo).
- IP `192.168.1.133` (DHCP). If it moves: `~/.ssh/find-thinkpad.sh` finds it by SSH key
  across `192.168.1.0/24` (WiFi MAC `C4-8E-8F-04-B5-73`).
- Hardened + proven: sshd Auto-start + auto-restart on failure; persistent firewall rule;
  pubkey+password auth both on; **survived a full reboot (back in 26s, no login)**; AC
  sleep disabled. Details in memory `[[thinkpad10-20c1-boot-blocked]]`.
- Remote PowerShell quoting is painful over cmd — pipe scripts via stdin:
  `ssh thinkpad10 'powershell -NoProfile -Command -' < script.ps1`.

**Status of channel #2 (replacement): NOT YET PROVEN.** Until this line says PROVEN, rule
in force. Terminal-copy commands: prefix with `clear;`/`cls`.
