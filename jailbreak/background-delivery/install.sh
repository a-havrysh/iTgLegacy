#!/bin/bash
# install.sh - copy the itglegacyd watchdog onto a jailbroken device and load it.
#
#   ./install.sh [ssh-host]
#
# `ssh-host` defaults to `itgphone`, the same alias scripts/devrun.sh uses; put
# the port, user, key and the legacy ssh-rsa algorithms in ~/.ssh/config.
#
# Installs exactly three files:
#   /usr/libexec/itglegacyd
#   /etc/itglegacyd.conf
#   /Library/LaunchDaemons/ru.kuzm.itglegacyd.plist
#
# uninstall.sh removes all three and unloads the job.

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
OUT_DIR="${SCRIPT_DIR}/out"
SSH_HOST="${1:-itgphone}"
SSH_OPTS="-o ConnectTimeout=8"

[ -x "${OUT_DIR}/itglegacyd" ] || { echo "[-] run ./build.sh first"; exit 1; }

echo "[+] target: ${SSH_HOST}"
ssh ${SSH_OPTS} "${SSH_HOST}" true || { echo "[-] cannot reach ${SSH_HOST}"; exit 1; }

echo "[+] copying"
scp ${SSH_OPTS} "${OUT_DIR}/itglegacyd"                "${SSH_HOST}:/usr/libexec/itglegacyd"
scp ${SSH_OPTS} "${SCRIPT_DIR}/itglegacyd.conf"        "${SSH_HOST}:/etc/itglegacyd.conf"
scp ${SSH_OPTS} "${SCRIPT_DIR}/ru.kuzm.itglegacyd.plist" \
	"${SSH_HOST}:/Library/LaunchDaemons/ru.kuzm.itglegacyd.plist"

echo "[+] loading"
ssh ${SSH_OPTS} "${SSH_HOST}" '
	chown root:wheel /usr/libexec/itglegacyd /Library/LaunchDaemons/ru.kuzm.itglegacyd.plist
	chmod 755 /usr/libexec/itglegacyd
	chmod 644 /Library/LaunchDaemons/ru.kuzm.itglegacyd.plist /etc/itglegacyd.conf
	launchctl unload /Library/LaunchDaemons/ru.kuzm.itglegacyd.plist 2>/dev/null
	launchctl load  /Library/LaunchDaemons/ru.kuzm.itglegacyd.plist
	sleep 2
	launchctl list | grep itglegacyd || echo "(not listed)"
'

echo ""
echo "[+] done. Watch it with:"
echo "      ssh ${SSH_HOST} tail -f /var/log/itglegacyd.log"
