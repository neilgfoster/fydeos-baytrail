DefinitionBlock ("ssdt-accel-mtx.aml", "SSDT", 2, "ICONIA", "ACCLMTX", 0x00000001)
{
    External (\_SB.I2C5.SHUB, DeviceObj)

    Scope (\_SB.I2C5.SHUB)
    {
        Name (_DSD, Package (0x02)
        {
            ToUUID ("daffd814-6eba-4d8c-8a91-bc9bbf4aa301"),
            Package (0x01)
            {
                Package (0x02)
                {
                    "mount-matrix",
                    Package (0x09)
                    {
                        "0", "1", "0",
                        "1", "0", "0",
                        "0", "0", "1"
                    }
                }
            }
        })
    }
}
