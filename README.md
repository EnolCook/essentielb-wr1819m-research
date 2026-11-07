# Essentiel B WR1819M / ALFA Network AX1800RM — research notes

> **Scope.** Independent reverse-engineering and fixes for the
> **Essentiel B "Routeur essB AX1800"** (model `WR1819M`), a MediaTek MT7621A + MT7915
> based router sold by Boulanger (France).
>
> The device is hardware-identical to the **ALFA Network AX1800RM** and ships with a
> vendor-forked OpenWrt firmware (`WR1819M_Boulange_V03D...`, kernel 4.4.198).
> Both brands can probably benefit from these notes; the specific vendor firmware we
> analyze here is the Boulanger build. Other ODM rebrands may differ in details.
>
> **This work was done on a device the authors own.** The goal is to let other owners
> of the same device understand it, fix its bugs, and regain full control over hardware
> they paid for.

## Why this exists

The vendor firmware works but ships with several defects that affect everyday use:

- **Broken IPv6 for Wi-Fi clients** — intermittent "Network Request Failed" in apps.
- **Slow 5 GHz SSID appearance** at boot (auto-channel scan with DFS).
- **Chinese DNS server** injected into the resolver (`114.114.114.114`).
- **Connectivity probe hits a Chinese host** (`www.baidu.com`) periodically.
- **Idle VPN daemons** (xl2tpd, pptpc) listening on the LAN with no configuration.
- **Multiple undocumented UID-0 vendor accounts** (`mtc`, `user`) baked into the image.
- **No root shell access** through normal channels — the stock SSH account passwords
  are unknown, and there is no publicly documented recovery path other than opening
  the case to attach a USB-TTL serial adapter.

Each of these is analyzed and, where possible, fixed, in the `docs/` folder.

## Status

| Topic | Status | File |
|---|---|---|
| Device identification & specs | ✅ complete | [docs/01-device.md](docs/01-device.md) |
| IPv6 bug root cause & fix | ✅ **diagnosed, fixed, validated on-device** | [docs/02-ipv6-bug.md](docs/02-ipv6-bug.md) |
| Slow 5 GHz boot & fix | ✅ complete | [docs/03-wifi-slow-boot.md](docs/03-wifi-slow-boot.md) |
| Security audit & hardening | ✅ complete | [docs/04-security-audit.md](docs/04-security-audit.md) |
| Root access via UART serial | ✅ reproducible procedure | [docs/05-root-via-uart-serial.md](docs/05-root-via-uart-serial.md) |
| Root access via web admin (no hardware!) | ✅ **validated exploit** | [docs/08-web-to-root-exploit.md](docs/08-web-to-root-exploit.md) |
| Firmware image format | 🧩 reference notes | [docs/06-firmware-format.md](docs/06-firmware-format.md) |
| Vendor accounts & hashes | 🧩 reference notes | [docs/07-vendor-accounts.md](docs/07-vendor-accounts.md) |
| Recovery rescue (U-Boot bypass) | ✅ procedure documented | [docs/09-recovery-rescue.md](docs/09-recovery-rescue.md) |

## Quick start

If you already have a root shell on the device (SSH or UART-serial),
the ready-to-run fixes are in [`scripts/`](scripts/):

```sh
# as root on the router:
sh apply-ipv6-fix.sh          # fix IPv6 on Wi-Fi + lock 5 GHz channel
sh apply-hardening.sh         # remove 114DNS, Baidu probe, idle VPN daemons, lock vendor accounts
```

If you **don't** have root yet — **no tools needed, just a browser:**

1. Download [`artifacts/unlock-root.tar.gz`](artifacts/unlock-root.tar.gz) from this repo.
2. Open `http://192.168.1.1` → log in (default: `admin` / `admin`).
3. Go to **System → Backup / Restore** → upload `unlock-root.tar.gz` as a restore.
4. Wait ~90 s for the reboot, then: `ssh root@192.168.1.1` (password: `ownerroot`).
5. **Change the password immediately:** run `passwd root` and pick something strong.

> **The default password `ownerroot` is public and identical for everyone
> using this file. Anyone on your LAN could SSH in if you don't change it.
> Do it right after your first login.**

That's it — **no opening the case, no serial adapter, no flashing, no command line**.
See [docs/08-web-to-root-exploit.md](docs/08-web-to-root-exploit.md) for details, or
[docs/05-root-via-uart-serial.md](docs/05-root-via-uart-serial.md) for the hardware
(UART serial) alternative.

## How we got here

This started with a simple problem: phones connected to the router kept
throwing "Network Request Failed" randomly. Here's the full path from that
bug report to the one-click root access solution.

1. **The bug** — intermittent "Network Request Failed" on phones connected
   via Wi-Fi, while Ethernet clients worked fine. Diagnosed as broken IPv6:
   the router advertises IPv6 via Router Advertisements and DHCPv6, but the
   global v6 path is dead. Phones prefer IPv6, try it, time out, and fail.
   The MediaTek Wi-Fi driver's IGMP/MLD snooping silently drops the Neighbor
   Discovery packets that would let IPv6 work properly.
   ([docs/02](docs/02-ipv6-bug.md))

2. **The wall** — the fix requires disabling RA/DHCPv6 and the Wi-Fi
   snooping, both of which need a root shell. The web admin UI doesn't
   expose these settings. SSH is running but the `root`, `mtc` and `user`
   accounts all have unknown passwords. There is no documented way in.

3. **Trying the obvious** — default credentials (`admin`/`admin`,
   `root`/`root`, `root`/`admin`, etc.): no luck on SSH. The web UI
   password (`admin`/`admin`) works but only gives access to the LuCI
   interface, not a shell. Searched forums, vendor docs, FCC filings — no
   root procedure exists publicly for this device.

4. **UART serial console** — opened the case, found header J4 with
   silkscreened VCC/RX/TX/GND, wired a CH340G USB-TTL adapter, entered
   OpenWrt failsafe mode. Got a root shell. Fixed the IPv6 bug, fixed the
   slow 5 GHz channel, ran a security audit (found Chinese DNS, Baidu
   connectivity probe, idle VPN daemons, undocumented UID-0 accounts),
   hardened everything.
   ([docs/05](docs/05-root-via-uart-serial.md))

5. **Making it accessible to everyone** — UART works but requires opening
   the case and a serial adapter most people don't own. We tried three
   paths to give root access without hardware:

   - **Crack the vendor `mtc` password** — the account is UID 0 with SSH
     access, baked into every unit. Tried ~1700 targeted candidates +
     rockyou with hashcat rules. No luck — the md5crypt hash still stands.
     ([docs/07](docs/07-vendor-accounts.md))

   - **Build a modified firmware .bin** — dump the flash, inject a known
     root password, reflash via the web upgrade UI. Blocked: the vendor
     uses a proprietary "mtc header" that a 4 KB gatekeeper binary
     validates with CRC32. Header format not reversed.
     ([docs/06](docs/06-firmware-format.md))

   - **Audit the web UI for a shortcut** — using the root shell from step
     4, read the LuCI source code. Found that the backup-restore endpoint
     runs `tar -C / -xzf` on any uploaded archive with **zero validation**.
     One tarball upload = arbitrary file write as root = game over.
     ([docs/08](docs/08-web-to-root-exploit.md))

6. **The solution** — that last finding is what ships as
   `unlock-root.tar.gz`. Upload it through the web UI, reboot, SSH in.
   No hardware, no flashing, no command line. The two other paths
   (password crack, firmware mod) became irrelevant.

## Help wanted

The main contribution we need:

- **Confirm on other units / builds.** Everything here was validated on one unit
  running `WR1819M_Boulange_V03D20210729154700_fr_B1559_01`. If you have a
  different build (newer Boulanger firmware, ALFA-branded AX1800RM, another
  rebrand), please open an issue with `sha256sum /dev/mtd3` and the firmware
  string from the web UI — this helps us track variants.

See [CONTRIBUTING.md](CONTRIBUTING.md) for details.

## Disclaimers

- Everything here was tested on a single unit. Your build revision may differ.
- Opening the case and flashing modified firmware **can brick the device.**
  We document a recovery path via U-Boot console
  ([docs/09-recovery-rescue.md](docs/09-recovery-rescue.md)) but it requires a
  USB-TTL serial adapter wired to the PCB header.
- This repository contains no proprietary vendor firmware binaries. Only the small
  utility binary needed for reverse-engineering (`mtc_upgrade`, 4 KB) and the stock
  `/etc/shadow` hashes (which are in-ROM and identical on every unit of the same
  firmware build) are included as artifacts.

## License

Code and documentation are released under the MIT license — see [LICENSE](LICENSE).
