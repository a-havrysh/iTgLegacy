#!/bin/bash
# uninstall.sh - remove the itglegacyd watchdog from a device.
#
#   ./uninstall.sh [ssh-host]
#
# Leaves nothing behind except the two log files, which it also deletes.
# Nothing else on the device was ever modified: no system file is patched, no
# MobileSubstrate dylib is installed, and the app itself is untouched.

set -e

SSH_HOST="${1:-itgphone}"
SSH_OPTS="-o ConnectTimeout=8"

echo "[+] target: ${SSH_HOST}"
ssh ${SSH_OPTS} "${SSH_HOST}" '
	launchctl unload /Library/LaunchDaemons/ru.kuzm.itglegacyd.plist 2>/dev/null
	rm -f /Library/LaunchDaemons/ru.kuzm.itglegacyd.plist
	rm -f /usr/libexec/itglegacyd
	rm -f /etc/itglegacyd.conf
	rm -f /var/log/itglegacyd.log /var/log/itglegacyd.log.1
	rm -f /var/log/itglegacyd.out /var/log/itglegacyd.err
	launchctl list | grep itglegacyd && echo "[!] still listed - reboot to clear" || echo "[+] gone"
'
