# Contributing

Three categories of help are especially welcome.

## 1. Crack the `mtc` hash

The single biggest win. The hash is in
[`artifacts/rom-shadow-hashes.txt`](artifacts/rom-shadow-hashes.txt),
md5crypt (hashcat mode 500).

```
hashcat -m 500 -a 0 artifacts/rom-shadow-hashes.txt <wordlist> -r <rule>
```

Our unsuccessful attempts so far are documented in
[docs/07-vendor-accounts.md](docs/07-vendor-accounts.md); please try other
wordlists / rule sets. If you crack it, open an issue. Don't put the plaintext
directly in the issue body unless we agree on disclosure first — email or
Signal are fine.

## 2. Reverse-engineer `mtc_upgrade.elf`

4 KB MIPSEL ELF in [`artifacts/mtc_upgrade.elf`](artifacts/mtc_upgrade.elf).
See [docs/06-firmware-format.md](docs/06-firmware-format.md) for what we know
and what's missing. We're looking for:

- The exact byte layout of the "mtc header" prepended to upgrade images.
- Which CRC algorithm (and which byte range) is validated by `CheckImageHead`.
- Whether `save_image_head` writes the header to a fixed offset in `/dev/mtd2`
  (and if so which).

A `docs/06a-mtc-header-format.md` describing the header, or a
`scripts/build-mtc-header.py` that produces a valid header for an arbitrary
payload, would be excellent contributions.

## 3. Find a web→root escalation in the vendor LuCI

The web UI runs as root, so any command-injection in a `cgi-bin` handler or
insecure file-write primitive is enough. Likely spots:

- Vendor custom controllers under `/usr/lib/lua/luci/controller/admin_mtk/`
  and `/usr/lib/lua/luci/mtc/`.
- Config-restore endpoints that write to disk.
- Diagnostic endpoints (ping, traceroute) that shell out.

If you're testing without having root first, work on a device you own and keep
a serial adapter nearby in case you need to recover.

## 4. Confirm on other units / builds

Everything here was validated on **one** unit running
`WR1819M_Boulange_V03D20210729154700_fr_B1559_01` with the specific SHA256s
in [`artifacts/mtd-dumps.sha256`](artifacts/mtd-dumps.sha256).

If you have a different build (newer Boulanger firmware, an ALFA-branded
AX1800RM with ALFA firmware, another rebrand), running
`sha256sum /dev/mtd3` and reporting the sum + the firmware string from the
web UI would already help us track variants.

## Style

- Documentation: Markdown, English, keep it technical but readable for someone
  who just wants to fix their router.
- Scripts: POSIX `sh`, no bashisms, no external dependencies beyond what the
  stock firmware ships. Idempotent (safe to re-run).
- No privacy-leaking data in commits (PRs will be reviewed for this).
