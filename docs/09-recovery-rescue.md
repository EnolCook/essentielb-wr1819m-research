# Recovery rescue via U-Boot console

> **When:** the router is stuck in U-Boot Web Recovery mode (red WLAN LED,
> serves only `192.168.1.1/index.html`, accepts no firmware upload because the
> image lacks the vendor "mtc header").
>
> **Cause:** the `mtc_upgrade save_image_head` command was run against a raw
> FIT image (no mtc header), which zeroed out the header reference in flash.
> U-Boot's default `bootcmd` checks that header at every boot and drops to Web
> Recovery when validation fails.

## Prerequisites

- USB-TTL serial adapter (CH340G or equivalent) wired to header **J4** on the
  PCB (see [docs/05](05-root-via-uart-serial.md) for pinout and wiring).
- Serial terminal at **115200 8N1** (PuTTY, minicom, or `screen`).
- The SPI flash still contains a valid FIT image at the stock offset
  (`0x90000`). If you never flashed custom firmware, this is the case.

## Procedure

### 1. Interrupt U-Boot

Power-cycle the router with the serial console open. Press **any key** when
you see:

```
Please choose the operation:
   1: Load system code to SDRAM via TFTP.
   2: Load system code then write to Flash via TFTP.
   3: Boot system code via Flash (default).
   4: Entr boot command line interface.
   ...
```

Select **`4`** to enter the U-Boot command line. You get a `MT7621 #` prompt.

### 2. Boot the FIT image manually

The stock firmware FIT image lives at SPI flash offset `0x90000`, size
`0x3754f4` bytes (varies slightly by build — use the size from your
`cat /proc/mtd` if you saved it, or this one for the Boulanger
`V03D20210729154700` build):

```
MT7621 # sf probe
MT7621 # sf read 0x80010000 0x90000 0x3754f4
MT7621 # bootm 0x80010000
```

This loads the FIT from flash into RAM and boots it directly, bypassing the
vendor header check. The router should come up normally.

### 3. Make it permanent

Once Linux is booted and you have a root shell (SSH or serial), the U-Boot
environment can be patched so the router always boots the FIT image directly,
permanently skipping the broken mtc header check:

```sh
# From the U-Boot console (before booting Linux), or via fw_setenv if
# available in Linux:

# Option A: from U-Boot console
MT7621 # setenv safeboot 'sf probe; sf read 0x80010000 0x90000 0x3754f4; bootm 0x80010000'
MT7621 # setenv bootcmd 'run safeboot'
MT7621 # saveenv
Saving Environment to SPI Flash...

# Option B: from Linux root shell (if fw_setenv is available)
fw_setenv safeboot 'sf probe; sf read 0x80010000 0x90000 0x3754f4; bootm 0x80010000'
fw_setenv bootcmd 'run safeboot'
```

After `saveenv`, every subsequent boot goes straight to Linux without checking
the mtc header. The Web Recovery mode is permanently bypassed.

### 4. Verify

Power-cycle the router (unplug, wait 5 seconds, plug back in). Watch the
serial console — you should see:

```
MT7621 # run safeboot
...
## Booting kernel from FIT Image at 80010000 ...
```

followed by normal Linux boot. If you see the U-Boot menu again instead,
repeat step 3.

## Side effects

- **Vendor web firmware upgrade is disabled.** Since `bootcmd` no longer
  calls the stock boot sequence, the `mtc_upgrade` header check is skipped
  entirely. This is intentional — you shouldn't flash vendor images without
  understanding them anyway.
- **U-Boot Web Recovery is still accessible** by interrupting U-Boot (step 1)
  and selecting option 2 (TFTP), but the web upload form at `192.168.1.1`
  will no longer trigger automatically.
- The `safeboot` environment variable survives factory resets (which only
  clear the OpenWrt overlay, not the U-Boot env sector).

## When you don't need this

If your router boots normally and you just want root access, skip this
entirely and use the [web admin → root exploit](08-web-to-root-exploit.md)
instead — it requires no hardware at all.
