#!/bin/zsh
# usage: measure.sh <label> [runs]
LABEL="$1"; RUNS="${2:-3}"
SSH="sshpass -p alpine ssh -o HostKeyAlgorithms=+ssh-rsa -o PubkeyAcceptedKeyTypes=+ssh-rsa -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null -o LogLevel=ERROR root@192.168.18.221"
for i in $(seq 1 $RUNS); do
  eval $SSH "'/tmp/wake >/dev/null 2>&1; killall -9 iTgLegacy 2>/dev/null; sleep 5; su mobile -c \"uiopen itglegacy://\"; sleep 12; grep -a PERF /var/mobile/Applications/*/Library/Caches/log.txt'" > /tmp/claude-501/-Users-alexanderhavrysh-Git-iOS-iTgLegacy/070bd45d-a71c-432d-8452-8891ef9cd28f/scratchpad/run_${LABEL}_$i.txt 2>&1
  echo "--- $LABEL run $i ---"
  grep -aE "image ready|PERF launch" /tmp/claude-501/-Users-alexanderhavrysh-Git-iOS-iTgLegacy/070bd45d-a71c-432d-8452-8891ef9cd28f/scratchpad/run_${LABEL}_$i.txt | sed 's/.*PERF/PERF/'
done
