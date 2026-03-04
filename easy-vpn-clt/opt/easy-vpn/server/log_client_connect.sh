#!/bin/bash

LOG_FILE="/var/log/openvpn/client_connections.log"
# shellcheck disable=SC2154
CLIENT_CN="$common_name"
CURRENT_DATETIME=$(date "+%Y-%m-%d %H:%M:%S")
echo "Client: $CLIENT_CN connected at $CURRENT_DATETIME" >> $LOG_FILE
