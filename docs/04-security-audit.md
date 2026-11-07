# Security audit & hardening

Audit of the stock firmware shipped with
`WR1819M_Boulange_V03D20210729154700_fr_B1559_01`.

## Executive summary

**Verdict: no active backdoor.** The firmware is a typical cheap-ODM OpenWrt fork
with the usual sloppy defaults rather than something malicious:

- No suspicious outbound connections to unknown hosts.
- No injected SSH authorized keys, empty root crontab.
- All NAT remote-access chains (`preroute_remote_web`, `port_forward`, `dmz_host`)
  are present but **empty**: no remote-access redirection is configured.
- No TR-069/ACS carrier-management client.

That said, the defaults have several sketchy choices worth cleaning up:

| Finding | Severity | Why |
|---|---|---|
| **Chinese DNS `114.114.114.114`** injected into resolv.conf | 🟠 | Queries leak to a third-party resolver by default |
| **Connectivity probe hits `www.baidu.com`** every so often | 🟡 | Phones home to a Chinese service for no good reason |
| **xl2tpd listening on udp:1701 with no tunnels configured** | 🟡 | Idle attack surface on LAN |
| **pptpc (PPTP client) running with empty config** | 🟡 | Idle attack surface |
| **MediaTek `wapp` daemon on tcp/udp:3517** | 🟡 | Known CVE class in MediaTek SDK ≤ 7.4.0.1; LAN-only exposure though |
| **UID-0 vendor accounts with unknown passwords** (`mtc`, `user`) | 🟠 | Permanent backdoor-shaped accounts in `/etc/shadow` |

## Findings in detail

### 1. Chinese DNS server injection

`/etc/config/mtcconnect` has:

```
option dns1 '8.8.8.8'
option dns2 '114.114.114.114'
```

A helper (`/usr/sbin/mtcdns.sh`) appends these as `nameserver` lines inside a
`#custom begin ... #custom end` block in `/tmp/resolv.conf.auto`. Result: DNS
queries that aren't answered by `dnsmasq` upstream (very few in practice, but
non-zero) can fall through to the Chinese resolver.

**Fix:**

```sh
uci set mtcconnect.connect.enabled='0'
uci delete mtcconnect.connect.dns1
uci delete mtcconnect.connect.dns2
uci commit mtcconnect
sed -i '/#custom begin/,/#custom end/d' /tmp/resolv.conf.auto
```

### 2. Baidu connectivity probe

`/etc/mtc/wanprobe.sh` curls `www.baidu.com` periodically to check WAN
reachability. This is both a privacy issue (phones home) and a reliability
issue (the probe fails for everyone when Baidu or the route to it hiccups).

**Fix:** redirect the probe to any neutral host:

```sh
cp /etc/mtc/wanprobe.sh /etc/mtc/wanprobe.sh.bak
sed -i 's|www\.baidu\.com|www.openwrt.org|g' /etc/mtc/wanprobe.sh
```

### 3. Idle VPN daemons (xl2tpd, pptpc)

Both daemons are enabled by default and running, with **no configuration**
(all tunnel sections in `/etc/xl2tpd/xl2tpd.conf` are commented out,
`/var/run/pptpc/pptpc.conf` is empty). In AP mode, they are pure attack surface
on the LAN.

**Fix:**

```sh
/etc/init.d/xl2tpd disable
/etc/init.d/xl2tpd stop
/etc/init.d/mtcpptpc disable       # vendor-specific name for pptpc
/etc/init.d/mtcpptpc stop
```

### 4. EasyMesh / `wapp` daemon

`EasyMesh` is **disabled** in config (`EasyMeshMode='0'`), but the init script
`/etc/rc.d/S99z2_easymesh` still launches the `wapp` MediaTek Wi-Fi management
daemon at every boot. `wapp` listens on tcp/udp:3517 on all interfaces.

MediaTek SDK ≤ 7.4.0.1 has a public RCE-class vulnerability in `wappd` (see
Fortinet advisory / Hacker News coverage). Our build is older and uses a slightly
different name (`wapp` vs `wappd`), but the lineage is the same.

**Fix:** removing the init symlink prevents it from being launched at boot by the
mesh script. The daemon is still respawned by `/lib/wifi/wifi_services.lua` when
Wi-Fi starts up — a cleaner kill requires neutering that script, which risks
breaking the driver. For AP-mode deployments on a private LAN the residual
exposure is low; if you run the device somewhere less trusted, consider
flashing OpenWrt mainline instead.

```sh
rm /etc/rc.d/S99z2_easymesh
```

### 5. UID-0 vendor accounts

`/rom/etc/passwd` and `/rom/etc/shadow` ship with **three UID-0 accounts in
addition to `root`**:

| User | UID | Shell | Hash location |
|---|---|---|---|
| `mtc` | 0 | **`/bin/ash`** | `/etc/shadow` |
| `user` | 0 | `/bin/false` | `/etc/passwd` (!) |
| `admin` | 0 | `/bin/false` | `/etc/passwd` (!) |

The `mtc` account is the most dangerous: it has a real shell and SSH password
login is enabled (`dropbear.PasswordAuth='on'` and `RootPasswordAuth='on'`).
Anyone who learns the password (which is baked into the firmware image) gets
root over SSH.

**Fix:** lock the two vendor accounts you don't need. `admin` is used by the
web UI logic, so leave its hash alone but keep its `/bin/false` shell.

```sh
# Lock mtc in shadow AND change its shell
awk -F: 'BEGIN{OFS=":"} $1=="mtc"{$2="!"} {print}' /etc/shadow > /tmp/s && \
  cp /tmp/s /etc/shadow && rm /tmp/s
awk -F: 'BEGIN{OFS=":"} $1=="mtc"{$7="/bin/false"} {print}' /etc/passwd > /tmp/p && \
  cp /tmp/p /etc/passwd && rm /tmp/p

# Lock user (hash lives in /etc/passwd on this image)
awk -F: 'BEGIN{OFS=":"} $1=="user"{$2="!"} {print}' /etc/passwd > /tmp/p && \
  cp /tmp/p /etc/passwd && rm /tmp/p
```

See [docs/07-vendor-accounts.md](07-vendor-accounts.md) for the actual hashes
(which are identical on every WR1819M of this firmware version).

## All-in-one hardening

See [`scripts/apply-hardening.sh`](../scripts/apply-hardening.sh) for a single
script that applies all of the above idempotently.

## Listening ports after hardening

On a hardened unit in AP mode, only four local-LAN-facing ports remain:

```
tcp 22   dropbear (SSH)
tcp 53   dnsmasq  (DNS)
tcp 80   uhttpd   (web UI)
tcp 3517 wapp     (MediaTek Wi-Fi mgmt — LAN only, see 4 above)
udp 53   dnsmasq
udp 3517 wapp
```
