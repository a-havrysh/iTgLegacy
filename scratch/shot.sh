#!/bin/zsh
S="sshpass -p alpine ssh -o HostKeyAlgorithms=+ssh-rsa -o PubkeyAcceptedKeyTypes=+ssh-rsa -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null -o LogLevel=ERROR root@192.168.18.221"
D=/tmp/claude-501/-Users-alexanderhavrysh-Git-iOS-iTgLegacy/070bd45d-a71c-432d-8452-8891ef9cd28f/scratchpad
eval $S "'/tmp/screenshot /tmp/s_$1.png >/dev/null 2>&1'"
sshpass -p alpine scp -o HostKeyAlgorithms=+ssh-rsa -o PubkeyAcceptedKeyTypes=+ssh-rsa -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null -o LogLevel=ERROR root@192.168.18.221:/tmp/s_$1.png $D/ >/dev/null 2>&1
echo "$D/s_$1.png"
