#!/bin/sh
# oath_generate_secrets.sh
# Deployed to /etc/openvpn/server/ by configure_server.
# generate_qr() in openvpn_functions.sh reads the issuer value from this file.
# Set your issuer string here — spaces should be URL-encoded manually as %20.
issuer='Lifeloop%20VPN'
userhash=$(openssl rand -hex 16)
base32=$(/usr/bin/oathtool --totp -v "$userhash" | grep Base32 | awk '{print $3}')
echo "User String:"
echo "otpauth://totp/$issuer:$1?secret=$base32"
echo "oath.secrets entry:"
echo "$1:$userhash"
