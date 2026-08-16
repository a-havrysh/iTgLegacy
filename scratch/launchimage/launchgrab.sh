#!/bin/zsh
# usage: launchgrab.sh <outdir> [frames]
# Refuses to report a run whose binary was swapped underneath it.
SCR="/private/tmp/claude-501/-Users-alexanderhavrysh-Git-iOS-iTgLegacy/070bd45d-a71c-432d-8452-8891ef9cd28f/scratchpad"
MINE=7566400
OUT="$1"; N="${2:-32}"
before=$($SCR/dsh "ls -l /Applications/Telegram.app/iTgLegacy" 2>/dev/null | awk '{print $5}')
if [ "$before" != "$MINE" ]; then echo "ABORT: device has $before bytes, not mine ($MINE)"; exit 1; fi
$SCR/dsh "/tmp/wake >/dev/null 2>&1; killall -9 iTgLegacy 2>/dev/null; sleep 6; rm -f /tmp/fg_*.png; /tmp/framegrab /tmp/fg $N 0 0 1 \"su mobile -c 'uiopen itglegacy://'\" > /tmp/fg.log 2>&1; sleep 8; grep -a 'PERF' /var/mobile/Applications/*/Library/Caches/log.txt" > $OUT.perf 2>&1
after=$($SCR/dsh "ls -l /Applications/Telegram.app/iTgLegacy" 2>/dev/null | awk '{print $5}')
if [ "$after" != "$MINE" ]; then echo "DISCARD: binary changed to $after during the run"; exit 1; fi
$SCR/dsh "cat /tmp/fg.log" > $OUT.frames 2>&1
rm -rf $OUT && mkdir -p $OUT
sshpass -p alpine scp -o HostKeyAlgorithms=+ssh-rsa -o PubkeyAcceptedKeyTypes=+ssh-rsa -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null -o LogLevel=ERROR "root@192.168.18.221:/tmp/fg_*.png" $OUT/ >/dev/null 2>&1
grep -E "captured" $OUT.frames
grep -aE "main rss|FIRST FRAME" $OUT.perf | sed 's/.*PERF/PERF/'
