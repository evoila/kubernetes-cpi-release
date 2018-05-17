#!/bin/sh
echo "root:$PASSWORD" | chpasswd
echo "jumphost:$PASSWORD" | chpasswd

exec /usr/sbin/sshd -D -e