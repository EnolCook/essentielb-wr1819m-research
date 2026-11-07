# Contributing

## 1. Confirm on other units / builds

This is the most useful contribution right now. Everything here was validated
on **one** unit running
`WR1819M_Boulange_V03D20210729154700_fr_B1559_01` with the specific SHA256s
in [`artifacts/mtd-dumps.sha256`](artifacts/mtd-dumps.sha256).

If you have a different build (newer Boulanger firmware, an ALFA-branded
AX1800RM with ALFA firmware, another rebrand), please open an issue with:

- The firmware string from the web UI (System → Software).
- `sha256sum /dev/mtd3` (once you have root).
- Whether `unlock-root.tar.gz` worked on your unit.

This helps us track variants and confirm the fixes apply broadly.

## 2. ~~Find a web→root escalation~~ — DONE

**Found and validated.** The LuCI backup-restore endpoint extracts any
uploaded tarball as root with zero validation. A pre-built tarball is at
[`artifacts/unlock-root.tar.gz`](artifacts/unlock-root.tar.gz) — see
[docs/08-web-to-root-exploit.md](docs/08-web-to-root-exploit.md).

## Bonus: firmware internals

The following are not needed for root access (the tarball method is simpler
and safer), but are documented as research artifacts for the curious:

- **Vendor `mtc` account hash** — md5crypt, uncracked. See
  [`artifacts/rom-shadow-hashes.txt`](artifacts/rom-shadow-hashes.txt) and
  [docs/07-vendor-accounts.md](docs/07-vendor-accounts.md).
- **`mtc_upgrade` header format** — the 4 KB MIPSEL ELF at
  [`artifacts/mtc_upgrade.elf`](artifacts/mtc_upgrade.elf) validates vendor
  firmware images. See [docs/06-firmware-format.md](docs/06-firmware-format.md).

## Style

- Documentation: Markdown, English, keep it technical but readable for someone
  who just wants to fix their router.
- Scripts: POSIX `sh`, no bashisms, no external dependencies beyond what the
  stock firmware ships. Idempotent (safe to re-run).
- No privacy-leaking data in commits (PRs will be reviewed for this).
