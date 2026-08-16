#!/bin/zsh
BIN="${1:-/Users/alexanderhavrysh/Git/iOS/iTgLegacy-worktrees/perf-premain/build/armv7/app/iTgLegacy.app/iTgLegacy}"
sshpass -p alpine scp -o HostKeyAlgorithms=+ssh-rsa -o PubkeyAcceptedKeyTypes=+ssh-rsa -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null -o LogLevel=ERROR "$BIN" root@192.168.18.221:/Applications/Telegram.app/iTgLegacy
