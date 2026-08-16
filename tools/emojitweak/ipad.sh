#!/bin/zsh
IPAD=${IPAD:-192.168.18.217}
export SSHPASS=${SSHPASS:-alpine}
OPTS=(-o ConnectTimeout=15 -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null
      -o HostKeyAlgorithms=+ssh-rsa -o PubkeyAcceptedKeyTypes=+ssh-rsa
      -o KexAlgorithms=+diffie-hellman-group1-sha1,diffie-hellman-group14-sha1
      -o PreferredAuthentications=password -o PubkeyAuthentication=no)

case "$1" in
  push) shift; sshpass -e scp -O $OPTS "$1" root@$IPAD:"$2" ;;
  pull) shift; sshpass -e scp -O $OPTS root@$IPAD:"$1" "$2" ;;
  *) sshpass -e ssh $OPTS root@$IPAD "$@" ;;
esac
