# Windows reference catalogue — Lenovo ThinkPad 10 20C1

Pulled T5 (2026-07-14) over channel #1 (`ssh thinkpad10`) while Windows is still the
intact, fully-functional reference OS — read-only, no risk to SSH. Purpose: capture
exact hardware IDs and vendor firmware/calibration blobs now, before eMMC
repartitioning starts and Windows becomes harder (or impossible) to reach for this.
Findings are folded into [`../hardware-status.md`](../hardware-status.md); this
directory holds the underlying raw data.

- `windows-pnp-device-inventory.txt` — full `Win32_PnPEntity` dump (name, hardware
  IDs, driver service) for every device Windows enumerates. Source of truth for chip
  identification; grep it for anything not yet in `hardware-status.md`.
- `windows-system-info.txt` — BIOS version (`GWET27WW (1.27)`, released 2015-01-12),
  board (`20C10026UK`, version `SKH47 I`), OEM string confirms `Intel BayTrail CRB
  Platform`.
- `windows-pnp-device-inventory-hdmi-connected.txt` — same dump repeated with an
  external display plugged into the micro-HDMI port (initial scan had nothing
  connected, so the HDMI video/audio devices were invisible — not because the port
  doesn't exist). Diff against the base inventory shows exactly two new devices:
  `Generic PnP Monitor` (video) and `LG TV SSCR2 (Intel SST Audio Device (WDM))`
  (HDMI audio endpoint) — confirms the port works, both video and audio.
- `firmware/` — vendor firmware/calibration blobs pulled from
  `C:\Windows\System32\DriverStore\FileRepository\...` and byte-verified against each
  source file's `Get-Item`-reported length after transfer (see gotcha below):
  - `wifi/43241b4rtecdc.bin` — Broadcom BCM43241 Wi-Fi dongle image (same chip already
    used for W4-820; no separate NVRAM file exists for this SKU, confirmed again here).
  - `bluetooth/BCM43241B0_002.001.013.0073.0076.hcd` — BT patchram for the same
    BCM43241 combo chip's Bluetooth side (loaded over UART, not the SDIO fn2 path).
    Standard `.hcd` format expected by Linux `hci_uart`/`btbcm`.
  - `nfc/*.ncd` — Broadcom BCM2079x NFC controller firmware, several
    revision/interface variants (B4/B5, embedded/i2c/pre) since the exact silicon
    revision on this unit isn't pinned down yet.
  - `camera/*.cpf` — per-sensor calibration for the two `atomisp` camera sensors
    (OV2722 front, IMX175 rear). Speculative/low-priority — Bay Trail `atomisp` Linux
    support is a known dead end (see the Iconia W4-820 archived board section).

## Transfer gotcha: silent truncation via `scp`/sftp

Plain `scp thinkpad10:C:\...\file dest` **silently truncates files at exactly 200KB
(204800 bytes)** for some files in `DriverStore\FileRepository` — `scp` exits 0 with
no error, so this is a real data-integrity trap, not just an inconvenience. Root cause
not identified. Workaround used here: read the file with PowerShell
`[IO.File]::ReadAllBytes()` + `[Convert]::ToBase64String()` over the normal `ssh`
exec channel, then `base64 -d` locally. **Always verify the resulting byte count
against `(Get-Item <path>).Length` from Windows before trusting a pulled file** —
two of the nine files pulled this session (`wifi/43241b4rtecdc.bin`,
`camera/IMX175_13P2BA832A.cpf`) hit this and had to be re-pulled via the base64
method; the rest were small enough to transfer intact via plain `scp` with
forward-slash paths (`thinkpad10:/Windows/...`, not backslash — backslash paths are
also silently rejected by `scp`, "No such file or directory", forward slashes work).
