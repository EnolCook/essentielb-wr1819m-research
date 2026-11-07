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
| Root access without opening the case | 🔧 in progress — see [open questions](#open-questions) | — |
| Firmware image format | 🧩 partially documented | [docs/06-firmware-format.md](docs/06-firmware-format.md) |
| Vendor accounts & hashes | 🔓 documented, crack open | [docs/07-vendor-accounts.md](docs/07-vendor-accounts.md) |

## Quick start

If you already have a root shell on the device (SSH or UART-serial),
the ready-to-run fixes are in [`scripts/`](scripts/):

```sh
# as root on the router:
sh apply-ipv6-fix.sh          # fix IPv6 on Wi-Fi + lock 5 GHz channel
sh apply-hardening.sh         # remove 114DNS, Baidu probe, idle VPN daemons, lock vendor accounts
```

If you **don't** have root yet, see [docs/05-root-via-uart-serial.md](docs/05-root-via-uart-serial.md)
for the current (hardware-opening) method.

## Open questions / help wanted

Three open items where contributions from other owners would be very useful:

1. **Crack the vendor `mtc` account password.**
   The `mtc` account is UID 0 with `/bin/ash` shell and is baked into every unit shipped
   with firmware `WR1819M_Boulange_V03D20210729154700_fr_B1559_01`.
   If someone cracks the md5crypt hash in [`artifacts/rom-shadow-hashes.txt`](artifacts/rom-shadow-hashes.txt),
   `ssh mtc@<router>` becomes a universal root entry point — **no case opening, no exploit needed**.
2. **Reverse-engineer `/sbin/mtc_upgrade`.**
   This 4 KB MIPSEL ELF binary ([`artifacts/mtc_upgrade.elf`](artifacts/mtc_upgrade.elf))
   is the gatekeeper for firmware uploads: it validates a custom "mtc header" prepended
   to every vendor image. Understanding that header format would allow building a
   modified `.bin` (= original + known root password) that the vendor's own
   *System → Upgrade firmware* UI accepts — the cleanest possible delivery for
   non-technical owners.
3. **Find a web→root escalation path in the vendor LuCI.**
   The web UI runs as root; most of these cheap-ODM firmwares expose at least one
   command-injection or insecure-upload endpoint. See
   [docs/06-firmware-format.md](docs/06-firmware-format.md) for what we know about the
   LuCI handlers.

See [CONTRIBUTING.md](CONTRIBUTING.md) for how to help.

## Disclaimers

- Everything here was tested on a single unit. Your build revision may differ.
- Opening the case and flashing modified firmware **can brick the device.**
  We document a recovery path (UART+failsafe) but it requires the same hardware you
  were trying to avoid in the first place.
- This repository contains no proprietary vendor firmware binaries. Only the small
  utility binary needed for reverse-engineering (`mtc_upgrade`, 4 KB) and the stock
  `/etc/shadow` hashes (which are in-ROM and identical on every unit of the same
  firmware build) are included as artifacts.

## License

Code and documentation are released under the MIT license — see [LICENSE](LICENSE).
