# The IPv6 bug (and how to fix it)

## Symptom

On a WR1819M configured in **AP mode** (bridged onto an upstream dual-stack router
like an ISP Livebox), Wi-Fi clients get intermittent app-level failures: *"Network
Request Failed"*, DNS "No address associated with hostname", slow page loads that
eventually time out. The same device on cellular, or wired behind the same upstream
router, works fine.

- IPv4 is perfect.
- Wi-Fi clients get IPv6 link-local and even global addresses from SLAAC.
- `ping6` to the upstream router's **link-local** address works (`fe80::...`).
- `ping6` to the upstream router's **global** address **times out**.
- `curl -6` to any dual-stack site hangs until timeout.
- Apps that use happy-eyeballs eventually fall back to IPv4 — but many don't,
  or fall back too slowly, producing the user-visible errors.

## Root cause (short)

The vendor firmware runs **two defects at once** that both break IPv6 Neighbor
Discovery on the Wi-Fi link:

1. **A rogue IPv6 router server is running on the AP**, even in AP mode:
   `odhcpd` advertises a ULA prefix via Router Advertisements and serves DHCPv6
   on the same bridged segment where the upstream real router is already doing it.
   This is a configuration bug: `dhcp.lan.ra='server'` + `dhcp.lan.dhcpv6='server'`
   should not be set when `system.workmode='ap'`.
   `omcproxy` (an IPv6 multicast proxy intended for router mode) is also running
   with `uplink wan/wan6 → downlink lan`, further mangling multicast on the bridge.
2. **MediaTek Wi-Fi IGMP/MLD snooping drops ND multicast.**
   The MediaTek driver has IGMP/MLD snooping enabled by default on every VAP
   (`IgmpSnEnable=1` in `/etc/wireless/mediatek/mt7915.dbdc.b*.dat`). Its
   implementation incorrectly drops the **solicited-node multicast Neighbor
   Solicitations** that Wi-Fi clients send to resolve the upstream router's
   global IPv6 address. Link-local ND still works because it piggybacks on
   periodic all-nodes RAs, but global ND never completes — and nothing on the
   Wi-Fi link can reach the upstream router over IPv6.

Defect #2 is the proximate cause of the user-visible problem; defect #1 pollutes
the network with a second IPv6 router and makes diagnostics confusing.

## Root cause (long)

### Why IPv6 needs multicast ND to work

IPv6 doesn't use ARP. To send a packet to a neighbor's IPv6 address, the sender
sends a *Neighbor Solicitation* (ICMPv6 type 135) to a **solicited-node multicast
address** derived from the target. The target replies with a *Neighbor
Advertisement*. Only then does traffic flow.

That multicast NS is a single unicast-looking L3 packet, but at L2 it's a
multicast Ethernet frame (destination `33:33:ff:xx:yy:zz`). Switches and APs
that do IGMP/MLD snooping decide whether to forward it based on whether they've
seen a client *join* the corresponding multicast group.

### What the driver does wrong

Android and other IPv6 clients **do not** explicitly join the solicited-node
multicast groups in a way the MediaTek snooper recognizes; the driver treats
unknown-dest multicast as droppable. Result: the NS goes out from the client
toward the AP, the AP floods it onto the wired segment, the upstream router
replies with an NA to the client's unicast L2, but the **reverse direction**
(the upstream router's solicited NS for the client) never reaches the Wi-Fi
client, because the AP's downlink snooping drops it.

Link-local works because clients receive **router advertisements** (sent to
`ff02::1` all-nodes) which are universally forwarded. So you end up with a
Wi-Fi client that thinks it has IPv6 configured (addresses + default route) but
can't actually exchange packets with the upstream router's global IPv6 address.

### How we proved it

Diagnosis on a phone connected to the Wi-Fi:

```sh
ping6 fe80::<router>%wlan0                         # link-local — works
ping6 <router-global-v6>                           # global — hangs
ip -6 neigh                                        # entry for global v6 stays INCOMPLETE/FAILED
```

Diagnosis on a wired host on the same segment: IPv6 works fully. So the problem
is strictly on the Wi-Fi path, strictly for ND to the global address.

After killing the snooping (`iwpriv rax0 set IgmpSnEnable=0` applied to all
VAPs), the ND entry becomes `REACHABLE` within seconds and `curl -6` succeeds.

## Fix

Two parts, both persistent across reboots. **Requires a root shell** (see
[docs/05-root-via-uart-serial.md](05-root-via-uart-serial.md) or the
[open questions](../README.md#open-questions-help-wanted) in the README).

### Part A — disable the rogue IPv6 server on the AP

```sh
uci set dhcp.lan.ra='disabled'
uci set dhcp.lan.dhcpv6='disabled'
uci set dhcp.lan.ndp='disabled'
uci commit dhcp

/etc/init.d/omcproxy disable
/etc/init.d/omcproxy stop
/etc/init.d/odhcpd restart
```

After this, only the upstream router advertises IPv6 on the segment, as it should.

### Part B — disable the Wi-Fi IGMP/MLD snooping

The snooping flag is stored in `/etc/wireless/mediatek/mt7915.dbdc.b{0,1}.dat`
and is applied at Wi-Fi start-up. There is no `uci` knob for it, so we disable
it at runtime via `iwpriv` and make it persistent by reapplying on each boot
from `/etc/rc.local`.

Add to `/etc/rc.local` **before** the final `exit 0`:

```sh
# Disable MediaTek Wi-Fi IGMP/MLD snooping on all VAPs for 2 minutes after boot
# (reapplies every 4s to cover late 5 GHz DFS bring-up)
(
  i=0
  while [ $i -lt 30 ]; do
    for ifc in ra0 ra1 ra2 ra3 rax0 rax1 rax2 rax3; do
      [ -d /sys/class/net/$ifc ] && iwpriv $ifc set IgmpSnEnable=0 >/dev/null 2>&1
    done
    i=$((i+1))
    sleep 4
  done
) &
```

Or just run [`scripts/apply-ipv6-fix.sh`](../scripts/apply-ipv6-fix.sh) via SSH as root.

## Validation

On a Wi-Fi client after applying the fix:

```sh
ip -6 neigh | grep <upstream-router-global-v6>
# expect: REACHABLE

ping6 -c 3 <upstream-router-global-v6>
# expect: 0% packet loss

curl -6 -o /dev/null -w '%{http_code} %{time_total}s\n' https://ipv6.google.com
# expect: 200  <~0.2s
```

All three conditions were met on the test device (a Samsung Galaxy phone on the
5 GHz VAP of a Boulanger WR1819M configured in AP mode behind a dual-stack ISP router).

## Why not just reflash OpenWrt

Mainline OpenWrt supports the AX1800RM (`ramips/mt7621` target), and reflashing
would give a cleaner result than patching the vendor firmware. However:

- The U-Boot web recovery on this exact batch rejects the mainline image due to
  a custom-header check (see [06-firmware-format.md](06-firmware-format.md)).
- `sysupgrade -n -F` from a failsafe/root shell does work — but you need a root
  shell first, which currently requires UART serial.
- The MT7915 AX radio has imperfect support in mainline OpenWrt on this SoC
  depending on version.

Patching the vendor firmware is a smaller, lower-risk fix for people who just
want their Wi-Fi to work.
