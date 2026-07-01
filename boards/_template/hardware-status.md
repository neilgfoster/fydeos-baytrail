# Hardware status matrix — <DEVICE NAME>

Statuses: `untested` / `broken` / `partial` / `works`.
Fill in the driver from `dmesg` once booted. Fix-location legend is in
[../../docs/hardware-status-legend.md](../../docs/hardware-status-legend.md).

| Subsystem | Status | Driver / mechanism | Fix location | Notes |
|-----------|--------|--------------------|--------------|-------|
| Boot (EFI handover) | untested | `CONFIG_EFI_MIXED` + handover proto | kernel | want `xloadflags` bit 0x04 set |
| Display / KMS | untested | | kernel/cmdline | |
| Backlight | untested | | kernel/cmdline | |
| Wi-Fi | untested | | kernel + rootfs firmware | |
| Bluetooth | untested | | kernel + firmware | |
| Audio | untested | | kernel + UCM (rootfs) | |
| Touchscreen | untested | | kernel + DMI/DSDT quirk | |
| Sensors | untested | | kernel | |
| eMMC | untested | `sdhci-acpi` | kernel | |
| USB | untested | | kernel | |
| Battery/PMIC | untested | | kernel | |
| Suspend | untested | | firmware-limited | |
