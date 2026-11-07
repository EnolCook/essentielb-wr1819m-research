#!/bin/sh
# apply-hardening.sh — clean up questionable stock-firmware defaults.
#
# Usage:  run as root on the router.
#           sh apply-hardening.sh
#
# What this does, all persistent across reboots and idempotent:
#   - Removes the Chinese DNS (114.114.114.114) and forced 8.8.8.8 that the
#     vendor inserts into resolv.conf by default.
#   - Replaces the "www.baidu.com" target of the vendor connectivity probe
#     with www.openwrt.org.
#   - Disables idle VPN daemons (xl2tpd, mtcpptpc) that listen on the LAN with
#     no configuration.
#   - Removes the EasyMesh init symlink (mesh is off by default but the script
#     still launches the wapp daemon for no reason).
#   - Locks the two vendor UID-0 accounts (mtc, user) that have baked-in
#     passwords in /rom.
#
# See docs/04-security-audit.md for the rationale behind each change.

set -e

echo "[1/5] Cleaning up DNS injection..."
uci set mtcconnect.connect.enabled='0'
uci -q delete mtcconnect.connect.dns1 2>/dev/null || true
uci -q delete mtcconnect.connect.dns2 2>/dev/null || true
uci commit mtcconnect
# Clean the currently-running resolv file too
sed -i '/#custom begin/,/#custom end/d' /tmp/resolv.conf.auto 2>/dev/null || true

echo "[2/5] Redirecting Baidu connectivity probe..."
if [ ! -f /etc/mtc/wanprobe.sh.bak ] && [ -f /etc/mtc/wanprobe.sh ]; then
    cp /etc/mtc/wanprobe.sh /etc/mtc/wanprobe.sh.bak
fi
if [ -f /etc/mtc/wanprobe.sh ]; then
    sed -i 's|www\.baidu\.com|www.openwrt.org|g' /etc/mtc/wanprobe.sh
fi

echo "[3/5] Disabling idle VPN daemons (xl2tpd, mtcpptpc)..."
for svc in xl2tpd mtcpptpc; do
    if [ -f /etc/init.d/$svc ]; then
        /etc/init.d/$svc disable 2>/dev/null || true
        /etc/init.d/$svc stop    2>/dev/null || true
    fi
done

echo "[4/5] Removing EasyMesh init symlink (mesh is off, no need to launch wapp from here)..."
rm -f /etc/rc.d/S99z2_easymesh

echo "[5/5] Locking vendor UID-0 accounts (mtc, user)..."
# Lock mtc's hash in /etc/shadow AND change its shell to /bin/false
if grep -q '^mtc:' /etc/shadow; then
    awk -F: 'BEGIN{OFS=":"} $1=="mtc"{$2="!"} {print}' /etc/shadow > /tmp/_s.$$
    cp /tmp/_s.$$ /etc/shadow
    rm /tmp/_s.$$
fi
if grep -q '^mtc:' /etc/passwd; then
    awk -F: 'BEGIN{OFS=":"} $1=="mtc"{$7="/bin/false"} {print}' /etc/passwd > /tmp/_p.$$
    cp /tmp/_p.$$ /etc/passwd
    rm /tmp/_p.$$
fi
# Lock user's hash (which lives in /etc/passwd on this image, not /etc/shadow)
if grep -q '^user:\$' /etc/passwd; then
    awk -F: 'BEGIN{OFS=":"} $1=="user"{$2="!"} {print}' /etc/passwd > /tmp/_p.$$
    cp /tmp/_p.$$ /etc/passwd
    rm /tmp/_p.$$
fi

sync
echo
echo "Done. Listening ports after hardening:"
netstat -lntup 2>/dev/null | awk 'NR==1 || /LISTEN|^udp/'
echo
echo "Note: 'wapp' on tcp/udp:3517 is a MediaTek Wi-Fi daemon respawned by the Wi-Fi driver."
echo "It is LAN-only exposure; see docs/04-security-audit.md for context."
