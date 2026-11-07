# Firmware image format (partial)

A good understanding of the vendor firmware image format is the key to the
cleanest possible root-access delivery: a modified `.bin` identical to the
original except for one changed account hash, flashable through the vendor's
own *System → Upgrade firmware* UI. This file documents what we know and what
we don't.

## What is in flash (mtd3, "firmware")

Dumped directly from the running device, `dd if=/dev/mtd3 of=fw.bin`,
the partition content is a **standard OpenWrt FIT image with no custom prefix**:

```
offset 0: d0 0d fe ed  # FDT_MAGIC  (FIT image header)
offset 4: 00 37 54 f4  # total size (big-endian) = 3 626 740 bytes
...
"MIPS OpenWrt FIT (Flattened Image Tree)"
"kernel@1"   — kernel subimage with crc32 + sha1 hashes
"fdt@1"      — flat device tree
"rootfs@1"   — squashfs rootfs
```

The FIT image itself is standard. Its sub-image integrity is already verified
by U-Boot through the usual `crc32`/`sha1` `hash` nodes present in the FIT
description. No vendor magic in there.

## What is on top of that for an upgrade image

An image **accepted by the vendor's web upgrade UI** is **not** the raw FIT image
above. It is `[opaque mtc header] + [FIT image]`.

The gatekeeper is **`/sbin/mtc_upgrade`** — a 4 KB MIPSEL ELF binary on the
device (extract it with `scp root@192.168.1.1:/sbin/mtc_upgrade .` once you
have root). Its symbol table exposes:

| Entrypoint | Underlying C function | Role |
|---|---|---|
| `check_image_head` | `CheckImageHead` | validates the prefix on an upload |
| `cut_image_head` | `CutImageInfoFromFile` | strips the prefix before flashing to mtd3 |
| `save_image_head` | `ReadAndSaveHeadInfoFromFile` | copies the prefix into mtd2 (Factory) for recovery |

### How the pipeline hangs together

In `/sbin/sysupgrade` on this device:

```sh
/sbin/mtc_upgrade check_image_head ${ARGV}    # line 188 — called by `sysupgrade -T`, fails if header is wrong
...
/sbin/mtc_upgrade save_image_head ${ARGV}     # line 253 — called before flash, stashes header into Factory
/sbin/mtc_upgrade cut_image_head ${ARGV}      # line 259 — writes the FIT image to mtd3 without the header
```

In LuCI, `luci.mtc.helper.image_supported(image)` just calls
`sysupgrade -T <image>` and that walks the chain above.

### What this means practically

- The FIT image we can read off mtd3 is **not directly uploadable** through the
  web UI — the vendor header is missing, and `sysupgrade -T` says
  "Image check head failed."
- A **modified `.bin` that reuses the ORIGINAL header verbatim** should pass the
  check, because `CheckImageHead` almost certainly only looks at the header
  itself, not at the trailing FIT. **This hypothesis is unverified** — the ELF
  has not been reversed yet.
- Alternatively, a modified image with a **correctly-reconstructed header**
  (matching whatever CRC / magic / length fields the vendor expects) should also
  pass. Doing this cleanly also needs the header format reversed.

### Why we don't have a sample valid header to inspect

- The partition where the header "would be" (as a prefix of mtd3) does not
  contain it — the pipeline strips it before writing to mtd3.
- `mtd2` (Factory) does contain a *saved* header after a successful flash,
  but most of mtd2 is occupied by the Wi-Fi EEPROM (MACs, calibration), and
  the saved header's offset within it is not obvious.
- Boulanger does not publish firmware upgrades for this model, so we can't
  download a known-good upgrade `.bin` to diff.

## Reversing `/sbin/mtc_upgrade`

4 KB of MIPSEL code, musl-linked. A few hours with
Ghidra/radare2/Binary Ninja should reveal:

- The header's magic / layout / length fields (exact structure).
- Which CRC algorithm, over which exact bytes, is checked.
- Whether a signature step (beyond CRC) is in play.

If you reverse this and want to help, please open a PR with a
`docs/06a-mtc-header-format.md` describing the struct, or send a patch to
`scripts/build-mtc-header.py` that can produce a valid header for an arbitrary
payload.

## The LuCI upgrade handler

For reference, the upload flow in the vendor LuCI:

```
POST /cgi-bin/luci/admin/system/upgrade/upload    (multipart "image" field)
  → action_upgrade_upload() in /usr/lib/lua/luci/controller/admin/system.lua
    → file saved to /tmp/firmware.img
    → hlp.image_supported(/tmp/firmware.img)
      → os.execute("sysupgrade -T /tmp/firmware.img")  ← the gate
    → if valid: return JSON with sha256, size, storage
POST /cgi-bin/luci/admin/system/upgrade/perform
  → /sbin/sysupgrade (with the saved /tmp/firmware.img)
    → platform_check_image()  (mt7621-* case → return 0, no custom check)
    → fwtool_check_image()    (standard OpenWrt metadata check)
    → mtc_upgrade save_image_head → mtc_upgrade cut_image_head → mtd write
```

The platform-level check is a no-op for this device (`return 0` in
`/lib/upgrade/platform.sh` for `mt7621-*`). The gate is really just
`mtc_upgrade check_image_head`.
