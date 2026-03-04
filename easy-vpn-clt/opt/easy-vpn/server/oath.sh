#!/bin/bash
# oath.sh — Fixed version
# Changes from original:
#   - Uses absolute path /etc/openvpn/server/oath.secrets instead of relying on CWD

OATH_SECRETS="/etc/openvpn/server/oath.secrets"
authFile=$1

user=$(head -1 "$authFile")
pass=$(tail -1 "$authFile")

if [ ! -f "$OATH_SECRETS" ]; then
    easy-vpn log "warn" "No secrets file found!"
    exit 1
fi

userHash=$(grep -i -m 1 "$user:" "$OATH_SECRETS" | cut -d: -f2-3)

if [ -z "$userHash" ]; then
    easy-vpn log "warn" "User not found"
    exit 1
fi

echo "$userHash" | grep -q -i :
TOTP_onlyCheck=$?
if [ $TOTP_onlyCheck -ne 0 ]; then
	easy-vpn log "info" "Authorizing user via TOTP code..."
	TOTPcode=$(oathtool --totp "$userHash")
	if [ "$TOTPcode" = "$pass" ]; then
		easy-vpn log "info" "TOTP code is correct"
		exit 0
	fi
	easy-vpn log "warn" "TOTP code is incorrect"
	exit 1
fi

echo "$pass" | grep -q -i :
passwordTOTPcheck=$?
if [ $passwordTOTPcheck -ne 0 ]; then
	easy-vpn log "info" "Authorizing user via password..."
	encryptPass=$(echo "$userHash" | cut -d: -f1)
	userHash=$(echo "$userHash" | cut -d: -f2)

	realPass=$(openssl passwd -1 -salt "$userHash" "$pass")
	if [ "$realPass" = "$encryptPass" ]; then
		easy-vpn log "info" "Password is correct"
		exit 0
	fi
	easy-vpn log "warn" "Password is incorrect"
	exit 1
fi

echo "Authorizing user via password and TOTP code..."
encryptPass=$(echo "$userHash" | cut -d: -f1)
userHash=$(echo "$userHash" | cut -d: -f2)
TOTPcode=$(oathtool --totp "$userHash")

TOTPpass=$(echo "$pass" | cut -d: -f2)
pass=$(echo "$pass" | cut -d: -f1)
realPass=$(openssl passwd -1 -salt "$userHash" "$pass")

if [ "$realPass" = "$encryptPass" ] && [ "$TOTPcode" = "$TOTPpass" ]; then
	easy-vpn log "info" "Password and TOTP code are correct"
	exit 0
fi

easy-vpn log "warn" "Password and/or TOTP code are incorrect"
easy-vpn log "warn" "Ensure that your password is formatted as 'password:TOTPcode'"
exit 1
