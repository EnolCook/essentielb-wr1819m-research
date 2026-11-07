# Device identification

## Sold as

| Brand | Market | Product name |
|---|---|---|
| **EssentielB** (Boulanger house brand) | France | *Routeur essB AX1800* |
| **ALFA Network** | International | **AX1800RM** |

Both brands ship the **same hardware**. The vendor firmware and some default
configuration may differ by rebrand; the analysis in this repo targets the
Boulanger variant.

## Hardware

| Part | Model |
|---|---|
| SoC | **MediaTek MT7621A** (2 cores / 4 threads MIPS 1004Kc @ 880 MHz) |
| RAM | 256 MiB (≈145 MiB free at runtime) |
| Flash | **16 MiB NOR** (`en25qh128a`) |
| Wi-Fi 2.4 GHz | MediaTek MT7915 (2×2) |
| Wi-Fi 5 GHz | MediaTek MT7915 (2×2), supports AX |
| Ethernet | MT7530 switch, 1 WAN + 4 LAN gigabit |
| USB | 1× USB 3.0 |

## Firmware

- Build string: `WR1819M_Boulange_V03D20210729154700_fr_B1559_01`
- Kernel: Linux **4.4.198** (`#0 SMP Sat Feb 12 12:16:12 UTC 2022`)
- Compiler banner: `LEDE GCC 5.4.0`
- Build host: `gwh@tongxin-ST58`
- U-Boot: `2018.09-svn2232 (Jan 05 2022)` + SPL `2018.09-svn786`
- LuCI web UI with vendor extensions under `/usr/lib/lua/luci/mtc/` and `/usr/lib/lua/luci/controller/admin_mtk/`
- Runs as an **OpenWrt/LEDE 17.01-SNAPSHOT fork** with MediaTek SDK additions

Device identifies to OpenWrt as `mt7621-rfb-ax-nor` (`/tmp/sysinfo/board_name`).

## Flash layout

As read from `/proc/mtd`:

| Partition | mtd | Size | Contents |
|---|---|---|---|
| `Bootloader` | mtd0 | 256 KiB (`0x40000`) | U-Boot |
| `Config` | mtd1 | 64 KiB | empty (`0xFF`) on observed unit |
| `Factory` | mtd2 | 256 KiB | Wi-Fi EEPROM (MACs, calibration) **+ saved copy of `mtc` image header** |
| `firmware` | mtd3 | 15.4 MiB | **FIT image**: kernel + fdt + rootfs (no header prefix on this partition) |
| `kernel` | mtd4 | 3.5 MiB | subpart of mtd3 |
| `rootfs` | mtd5 | 12 MiB | subpart of mtd3 |
| `rootfs_data` | mtd6 | 2.6 MiB | JFFS2 overlay (writable) |

- Root fs is a **squashfs** read-only at `/rom`, with a JFFS2 overlay providing the writable `/etc` etc.
- A firmware image accepted by the vendor web upgrade is **prefixed with an opaque "mtc header"**
  that is stripped by `/sbin/mtc_upgrade` before the FIT image is written to `mtd3`.
  The header is saved into `mtd2` (Factory). The format is **not yet reversed**;
  see [docs/06-firmware-format.md](06-firmware-format.md).

## OpenWrt support

The ALFA AX1800RM is supported by mainline OpenWrt (target `ramips/mt7621`).
A U-Boot web recovery method exists but has been reported blocked by the custom-header
check on this exact batch. `sysupgrade -F` from a failsafe/root shell works.

## Boot-time quirks

- The U-Boot boot menu intercepts the Reset/WPS button at power-on, latching
  the device into a "web-recovery" state (power LED solid, `http://192.168.1.1`,
  locally-administered MAC) instead of entering OpenWrt failsafe.
  Reaching standard OpenWrt failsafe (`Press the [f] key and hit [enter]...`)
  therefore requires **serial access**.
- At shutdown/reboot the stock MediaTek Wi-Fi driver triggers a cosmetic kernel
  oops in `rt_pci_shutdown` ("panic in 5 seconds"), which itself resets the
  device — the reboot proceeds normally.
