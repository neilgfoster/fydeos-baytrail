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

**Status of channel #2 (replacement): FUNCTIONALITY PROVEN (2026-07-14), rule STILL IN
FORCE.** The rescue image (`boards/thinkpad10-20c1/rescue/`, built by
`scripts/build-rescue-image.sh`) boots standalone, joins WiFi interactively, and gives
password-auth SSH root — verified across **two independent successful boots** (fresh
WiFi join + password entry each time, persisted password reused correctly on the 2nd).
But it is **not yet an independent fallback**: it only boots via a one-time
`{fwbootmgr} bootsequence` entry that must be armed **from Windows over channel #1**
(`bcdedit /set {fwbootmgr} bootsequence <guid>`) — there is no persistent boot-menu
entry yet. If channel #1 were actually lost, there is currently no way to reach channel
#2 without physical access + the firmware Boot Menu to select it some other way. **The
rule stays in force until a persistent (non-one-time) boot-menu entry makes channel #2
reachable without channel #1 already being alive** — see `PROGRESS.md` T4 for the
next-session plan to close this gap.

Known limitations of the rescue image (see `PROGRESS.md` T4 for full detail): WiFi
SSID/password must be entered interactively every boot (by design, never baked in);
`reboot`/`poweroff` from within it do not reliably return to Windows (a hard power-off
is the proven path back); password reset for the rescue root account is done by
overwriting `S:\EFI\Rescue\rescue-shadow.txt` over channel #1, or via the local
console's unconditional root shell if channel #1 is also down.

Terminal-copy commands: prefix with `clear;`/`cls`.
