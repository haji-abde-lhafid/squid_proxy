#!/bin/bash
if [ "$#" -ne 2 ]; then
    echo "Usage: $0 <username> <password>"
    exit 1
fi
htpasswd -b /etc/squid/passwords "$1" "$2"
systemctl reload squid
echo "User $1 added successfully"