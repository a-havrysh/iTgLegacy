#!/bin/zsh
# usage: cold.sh <label> [runs]   - real cold launches: kill, then open, no grabber
SCR="/private/tmp/claude-501/-Users-alexanderhavrysh-Git-iOS-iTgLegacy/070bd45d-a71c-432d-8452-8891ef9cd28f/scratchpad"
MINE=7566496
LABEL="$1"; RUNS="${2:-3}"
for i in $(seq 1 $RUNS); do
  sz=$($SCR/dsh "ls -l /Applications/Telegram.app/iTgLegacy" 2>/dev/null | awk '{print $5}')
  [ "$sz" != "$MINE" ] && { echo "ABORT run $i: binary is $sz not $MINE"; return 1; }
  $SCR/dsh "/tmp/wake >/dev/null 2>&1; killall -9 iTgLegacy 2>/dev/null; su mobile -c 'uiopen itglegacy://'; sleep 14; grep -a PERF /var/mobile/Applications/*/Library/Caches/log.txt" > $SCR/cold_${LABEL}_$i.txt 2>&1
  printf "%-10s run %d  " "$LABEL" $i
  grep -aoE "\(tap \+[0-9]+ ms\): (main|FIRST FRAME)" $SCR/cold_${LABEL}_$i.txt | sed 's/(tap +//; s/ ms)://' | tr '\n' ' '
  echo
done
