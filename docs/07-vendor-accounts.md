# Vendor UID-0 accounts

The stock firmware ships three vendor-defined UID-0 accounts, baked into the
squashfs image (`/rom/etc/passwd` and `/rom/etc/shadow`) and therefore
**identical on every unit with firmware build
`WR1819M_Boulange_V03D20210729154700_fr_B1559_01`**.

## The accounts (verbatim from `/rom`)

`/rom/etc/passwd`:

```
root:x:0:0:root:/root:/bin/false
mtc:x:0:0:mtc:/:/bin/ash
daemon:*:1:1:daemon:/var:/bin/false
ftp:*:55:55:ftp:/home/ftp:/bin/false
network:*:101:101:network:/var:/bin/false
nobody:*:65534:65534:nobody:/var:/bin/false
user:$1$d87shxEL$qEIMdCo0Xp9h3xb8TtiII/:0:0:Adminstrator:/:/bin/false
dnsmasq:x:453:453:dnsmasq:/var/run/dnsmasq:/bin/false
```

`/rom/etc/shadow`:

```
root:$1$RQTh1mP9$EY63rRwvVeNTNDtMRAXzg0:0:0:99999:7:::
mtc:$1$cGxiTn6s$k6NTy/dSuGwmz6CF4ZKx9.:18507:0:99999:7:::
daemon:*:0:0:99999:7:::
ftp:*:0:0:99999:7:::
network:*:0:0:99999:7:::
nobody:*:0:0:99999:7:::
dnsmasq:x:0:0:99999:7:::
```

Three accounts have UID 0 and thus are root-equivalent:

| User | UID | Shell | Hash location in `/rom` |
|---|---|---|---|
| `root` | 0 | `/bin/false` (!) | `/rom/etc/shadow` |
| `mtc` | 0 | **`/bin/ash`** | `/rom/etc/shadow` |
| `user` | 0 | `/bin/false` | **`/rom/etc/passwd`** (unusual but intentional) |

An `admin` account is also created at first boot by the web-UI flow (and its
hash lives in `/etc/passwd` on the running overlay), with the password printed
on the device sticker or `admin`/`admin` defaults. It is not a `/rom` entry
and is not universal — each unit has its own `admin` hash after the user
changes the password.

See [`artifacts/rom-shadow-hashes.txt`](../artifacts/rom-shadow-hashes.txt) for
the universal hashes above in ready-to-feed form for hashcat.

## Why `mtc` is the valuable target

Of the three universal UID-0 accounts, only **`mtc`** combines:
- UID 0 (full root)
- `/bin/ash` (a real interactive shell — `root` has `/bin/false` so is useless
  even if its password is known)
- SSH `PasswordAuth` + `RootPasswordAuth` both `on` in the stock dropbear config

→ Whoever discovers the plaintext password for `mtc` immediately gets
`ssh mtc@<any-WR1819M-of-this-build>` as root, with no further effort and no
hardware access. That is the single biggest unlock this project is chasing.

## What we tried (unsuccessfully)

- `rockyou.txt` + hashcat `best64.rule` → nothing.
- Targeted dictionaries on **~1 700 candidates** derived from everything
  identifiable about the device (brand names, product names, build artifacts,
  developer username and build host from the kernel banner, SDK names, French
  words, Chinese ODM naming conventions, common vendor patterns like
  `admin@123`, `mtc1234`, etc.) → nothing.
- Web searches for the hash, the salt, and the account name → no public
  cracked copy.

Conclusion: the password was most likely chosen randomly (or by an internal
convention we don't have visibility into) by the ODM that built this firmware
for Boulanger. It is **not** a MediaTek-SDK default — those don't ship with a
password at all.

## Help wanted: crack it

If you have GPU time to spare, the hash is a plain md5crypt (`$1$`), which
hashcat eats fast (~20 MH/s on a modern GPU). Try:

```
hashcat -m 500 -a 0 rom-shadow-hashes.txt wordlist.txt -r rules.rule
```

Good wordlists to throw at it:
- HashMob's cracked-combined, Weakpass v2, rockyou2024, hashes.org dumps
- Any leaked "cn-common" or vendor-dev wordlists

If you crack it, please open an issue — this single fact unlocks root for
every owner of this device.

## Related: what to do once you have root

Independently of the `mtc` crack, if you already have root (via UART serial),
the first thing to do is **lock these vendor accounts** so nobody else can use
them against you if they ever do find the password. See
[`scripts/apply-hardening.sh`](../scripts/apply-hardening.sh) or the "Vendor
accounts" section of [docs/04-security-audit.md](04-security-audit.md).
