#!/bin/sh
# apply-ipv6-fix.sh — fix IPv6 on Wi-Fi + pin 5 GHz to a non-DFS channel.
#
# Usage:  run as root on the router (SSH or UART serial).
#           sh apply-ipv6-fix.sh
#
# What this does, all persistent across reboots:
#   - Disables the rogue IPv6 RA/DHCPv6 server that the vendor firmware runs
#     even when the device is in AP mode.
#   - Disables omcproxy (multicast proxy, inappropriate for an AP).
#   - Disables MediaTek Wi-Fi IGMP/MLD snooping on every VAP (both bands).
#     This is the fix that makes global IPv6 ND actually complete over Wi-Fi.
#   - Writes an /etc/rc.local snippet that reapplies the snooping fix on each
#     boot (needed because the driver resets it at wifi start-up).
#   - Pins the 5 GHz channel to 48 (non-DFS) so the SSID appears quickly at
#     boot and clients discover it actively.
#
# Safe to re-run: all steps are idempotent.

set -e

CHAN5G=48    # change if you prefer 36 / 40 / 44

echo "[1/4] Disabling rogue RA/DHCPv6 server on LAN..."
uci set dhcp.lan.ra='disabled'
uci set dhcp.lan.dhcpv6='disabled'
uci set dhcp.lan.ndp='disabled'
uci commit dhcp

echo "[2/4] Stopping omcproxy and disabling at boot..."
/etc/init.d/omcproxy stop     2>/dev/null || true
/etc/init.d/omcproxy disable  2>/dev/null || true

echo "[3/4] Disabling Wi-Fi IGMP/MLD snooping live + persistent..."
# Live apply on every current VAP
for ifc in ra0 ra1 ra2 ra3 rax0 rax1 rax2 rax3; do
    [ -d "/sys/class/net/$ifc" ] || continue
    iwpriv "$ifc" set IgmpSnEnable=0 >/dev/null 2>&1 || true
done

# Make it persistent through /etc/rc.local
RC=/etc/rc.local
MARKER='# --- IPv6 fix: disable MediaTek Wi-Fi IGMP/MLD snooping ---'
if ! grep -qF "$MARKER" "$RC"; then
    # Insert before the final `exit 0`
    TMP=$(mktemp)
    awk -v m="$MARKER" '
      /^exit 0/ && !done {
        print m
        print "("
        print "  i=0"
        print "  while [ $i -lt 30 ]; do"
        print "    for ifc in ra0 ra1 ra2 ra3 rax0 rax1 rax2 rax3; do"
        print "      [ -d /sys/class/net/$ifc ] && iwpriv $ifc set IgmpSnEnable=0 >/dev/null 2>&1"
        print "    done"
        print "    i=$((i+1))"
        print "    sleep 4"
        print "  done"
        print ") &"
        print ""
        done=1
      }
      {print}
    ' "$RC" > "$TMP"
    mv "$TMP" "$RC"
    chmod +x "$RC"
fi

echo "[4/4] Pinning 5 GHz to channel $CHAN5G (non-DFS)..."
uci set mtcwireless.wlan_5g.channel="$CHAN5G"
uci set mtcwireless.wlan_5g.AutoChannelSelect='0'
uci commit mtcwireless
sed -i -e "s/^Channel=0\$/Channel=$CHAN5G/" \
       -e 's/^AutoChannelSelect=3$/AutoChannelSelect=0/' \
       /etc/wireless/mediatek/mt7915.dbdc.b1.dat
iwpriv rax0 set Channel="$CHAN5G" >/dev/null 2>&1 || true

sync

echo
echo "Done. To validate, from a Wi-Fi client:"
echo "  ping6 <your-upstream-router-global-v6>   # expect 0% loss"
echo "  curl -6 -o /dev/null -w '%{http_code}\\n' https://ipv6.google.com   # expect 200"
