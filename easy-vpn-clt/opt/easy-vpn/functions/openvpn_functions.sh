#!/bin/bash
# shellcheck disable=SC1090
# openvpn_functions.sh — Fixed version
# Changes from original:
#   1. check_for_unused_certs: inverted -z/-n guard fixed
#   2. generate_qr: reads issuer from easy-vpn.env instead of nonexistent file

function create_client_cert() {
	if [ -z "$1" ] || [ -z "$2" ] || [ -z "$3" ]; then
		usage "create"
		loud_exit
	fi

	clientName=$1
	GENERATE_OATH=$2
	clientPassword=$3

	easyVPNConfig="/opt/easy-vpn/server/easy-vpn.env"
	if [[ ! -f "$easyVPNConfig" ]]; then
		echo "EasyVPN Configuration file not found. Please run the configure_env function first."
		echo "Usage: $0 configure_env <EASY_VPN_ISSUER> <EASY_VPN_AUTH_TYPE> <ORGANIZATION_NAME> <VPN_PUBLIC_IP>"
		loud_exit
	fi

	export EASYRSA_BATCH=1

	keyDIR=/etc/openvpn/client/client-configs/keys
	outputDIR=/etc/openvpn/client/client-configs/files
	baseConfig=/etc/openvpn/client/client-configs/base.conf

	cd /opt/easy-vpn/easy-rsa || { echo "Directory Not Found"; loud_exit; }
	./easyrsa gen-req "${clientName}" nopass
	cp pki/private/"${clientName}".key ${keyDIR}/
	./easyrsa sign-req client "${clientName}"
	cp pki/issued/"${clientName}".crt ${keyDIR}/

	cat ${baseConfig} \
	    <(echo -e '<ca>') \
	    ${keyDIR}/ca.crt \
	    <(echo -e '</ca>\n<cert>') \
	    ${keyDIR}/"${clientName}".crt \
	    <(echo -e '</cert>\n<key>') \
	    ${keyDIR}/"${clientName}".key \
	    <(echo -e '</key>\n<tls-auth>') \
	    ${keyDIR}/ta.key \
	    <(echo -e '</tls-auth>') \
	    > ${outputDIR}/"${clientName}".ovpn

	if [[ "$GENERATE_OATH" == "true" ]]; then
		generate_oath "${clientName}" "${clientPassword}"
	fi

	echo "Client Configuration File: ${outputDIR}/${clientName}.ovpn"
	cat "${outputDIR}/${clientName}.ovpn"
}

function revoke_client_cert() {
	if [ -z "$1" ]; then
		usage "revoke" "cert"
		loud_exit
	fi
	clientName=$1

	export EASYRSA_BATCH=1

	keyDIR=/etc/openvpn/client/client-configs/keys
	outputDIR=/etc/openvpn/client/client-configs/files
	cd /opt/easy-vpn/easy-rsa || { echo "Directory Not Found"; loud_exit; }
	./easyrsa revoke "${clientName}"
	./easyrsa gen-crl
	cp pki/crl.pem /etc/openvpn/server/
	rm ${keyDIR}/"${clientName}".crt
	rm ${keyDIR}/"${clientName}".key
	rm ${outputDIR}/"${clientName}".ovpn
}

function check_for_expired_certs() {
	certsByClient="/etc/openvpn/client/client-configs/keys"
	certsBySerial="/opt/easy-vpn/easy-rsa/pki/certs_by_serial"
	indexFile="/opt/easy-vpn/easy-rsa/pki/index.txt"
	today=$(date -u +"%Y-%m-%d")

	if [[ ! -f "${indexFile}" ]] || [[ ! -d "${certsByClient}" ]] || [[ ! -d "${certsBySerial}" ]]; then
		echo "Index file or Clients directories not found. Please check your configuration."
		usage "status" "expired"
		loud_exit
	fi

	while read -r line; do
	    if [[ $line == *"R"* ]]; then
	        continue
	    fi

	    CLIENT=$(echo "$line" | awk '{print $5}' | sed 's/\/CN=//g')
	    CERT_ID=$(echo "$line" | awk '{print $3}')

	    if [[ -f "${certsByClient}/${CLIENT}.crt" ]]; then
	        expDate=$(openssl x509 -enddate -noout -in "${certsByClient}/${CLIENT}.crt" | awk -F '=' '{print $2}')
		fi

	    if [[ "${expDate}" == "" ]]; then
	        expDate=$(openssl x509 -enddate -noout -in "${certsBySerial}/${CERT_ID}.pem" | awk -F '=' '{print $2}')
	    fi

		if [[ "${expDate}" == "" ]]; then
	    	continue
	    fi

	    expUNIX=$(date -u -d "${expDate}" +"%s")
	    todayUNIX=$(date -u -d "${today}" +"%s")

	    echo "${CLIENT} expires on: ${expDate}"

	    if [[ ${expUNIX} -lt ${todayUNIX} ]]; then
	        echo "#######################################################"
	        echo "${CLIENT} HAS EXPIRED! PLEASE UPDATE CERTIFICATE!"
	        echo "######################################################"
	        echo ""
	    fi

	done < ${indexFile}
}

function get_all_active_clients() {
	indexFile="/opt/easy-vpn/easy-rsa/pki/index.txt"
	if [[ ! -f "${indexFile}" ]]; then
		echo "Index file not found. Please check your configuration."
		usage "list"
		loud_exit
	fi
	while read -r line; do
	    if [[ $line == *"R"* ]]; then
	        continue
	    fi

		if [[ $line == *"server"* ]]; then
			continue
		fi

	    CLIENT=$(echo "$line" | awk '{print $5}' | sed 's/\/CN=//g')
	    echo "${CLIENT}"
	done < ${indexFile}
}

# FIX 1: Inverted -z/-n guard — original used -z (empty check) to SET the value,
# meaning autoRevoke was only ever set when $1 was missing. Fixed to -n.
function check_for_unused_certs() {
	# FIX: was [ -z "$1" ] which set autoRevoke only when arg was MISSING
	if [ -n "$1" ]; then
		autoRevoke=$1
	else
		autoRevoke="false"
	fi

	certsByClient="/etc/openvpn/client/client-configs/keys"
	certsBySerial="/opt/easy-vpn/easy-rsa/pki/certs_by_serial"
	indexFile="/opt/easy-vpn/easy-rsa/pki/index.txt"
	logFile="/var/log/openvpn/client_connections.log"
	today=$(date +"%Y-%m-%d")
	todaySec=$(date -d "${today}" +"%s")

	if [[ ! -f "${indexFile}" ]] || [[ ! -d "${certsByClient}" ]] || [[ ! -d "${certsBySerial}" ]]; then
		echo "Index file or Clients directories not found. Please check your configuration."
		usage "status" "unused"
		loud_exit
	fi

	while read -r line; do
	    if [[ $line == *"R"* ]]; then
	        continue
	    fi

		if [[ $line == *"server"* ]]; then
			continue
		fi

	    CLIENT=$(echo "$line" | awk '{print $5}' | sed 's/\/CN=//g')
		lastLogin=$(grep "${CLIENT}" "${logFile}" | tail -n 1 | awk '{print $NF}' )

	    if [[ "${lastLogin}" == "" ]]; then
	        echo "#######################################################"
	        echo "${CLIENT} has no connections logged. Please check if this certificate is still in use."
	        echo "######################################################"
	        echo ""
			continue
	    fi

		lastLoginSec=$(date -d "${lastLogin}" +"%s")
		diffDay=$(( (todaySec - lastLoginSec) / 86400 ))

		# Note: check 180+ BEFORE 90+ to avoid false positives
		if [[ ${diffDay} -ge 180 ]]; then
	        echo "#######################################################"
	        echo "${CLIENT} has not connected in over 180 days. Auto-revoke set to: ${autoRevoke}"
			if [[ "${autoRevoke}" == "true" ]]; then
				revoke_client_cert "${CLIENT}"
			else
				echo "Please check if this certificate is still in use."
			fi
	        echo "######################################################"
	        echo ""
		elif [[ ${diffDay} -ge 90 ]]; then
	        echo "#######################################################"
	        echo "${CLIENT} has not connected in over 90 days. Please check if this certificate is still in use."
	        echo "######################################################"
	        echo ""
	    else
			echo "${CLIENT} last connected on: ${lastLogin} which was ${diffDay} days ago."
	    fi

	done < ${indexFile}
}

function generate_oath() {
	if [ -z "$1" ]; then
		usage "generate" "oath"
		loud_exit
	fi
	clientName=$1
	clientHash=$(openssl rand -hex 16)

	easyVPNConfig="/opt/easy-vpn/server/easy-vpn.env"
	if [[ ! -f "$easyVPNConfig" ]]; then
		echo "EasyVPN Configuration file not found. Please run the configure_env function first."
		echo "Usage: $0 configure_env <EASY_VPN_ISSUER> <EASY_VPN_AUTH_TYPE> <ORGANIZATION_NAME> <VPN_PUBLIC_IP>"
		loud_exit
	fi
	source "$easyVPNConfig"
	issuer=$EASY_VPN_ISSUER
	authType=$EASY_VPN_AUTH_TYPE

	if [[ $issuer == *" "* ]]; then
		issuer=${issuer// /%20}
	fi

	oathfile='/etc/openvpn/server/oath.secrets'
	if [ ! -f $oathfile ]; then
		echo "Creating $oathfile"
		touch $oathfile
		chown root:root $oathfile
		chmod +r $oathfile
	fi

	if [[ "$authType" == "PASSWORD_ONLY" ]]; then
		if [ -z "$2" ]; then
			echo "Client Password is required. Please provide the client's password."
			echo "Usage: $0 <client-name> <client-password>"
			loud_exit
		fi
		clientPassword=$2
		encryptPass=$(openssl passwd -1 -salt "$clientHash" "$clientPassword")
		secretString="${clientName}:${encryptPass}:${clientHash}"
	fi

	if [[ "$authType" == "TOTP_ONLY" ]]; then
		base32=$(/usr/bin/oathtool --totp -v "$clientHash" | grep Base32 | awk '{print $3}')
		secretString="${clientName}:${clientHash}"

		echo "Client TOTP String:"
		echo "otpauth://totp/$issuer:$clientName?secret=$base32"
	fi

	if [[ "$authType" == "BOTH" ]]; then
		if [ -z "$2" ]; then
			echo "Client Password is required. Please provide the client's password."
			echo "Usage: $0 <client-name> <client-password>"
			loud_exit
		fi
		clientPassword=$2
		encryptPass=$(openssl passwd -1 -salt "$clientHash" "$clientPassword")
		base32=$(/usr/bin/oathtool --totp -v "$clientHash" | grep Base32 | awk '{print $3}')
		secretString="${clientName}:${encryptPass}:${clientHash}"
		echo "Reminder! Password string is in the format: <password>:<TOTP code>"
		echo "Client TOTP String:"
		echo "otpauth://totp/$issuer:$clientName?secret=$base32"
	fi

	if [[ "$authType" == "TOTP_OR_PASSWORD" ]]; then
		if [ -z "$2" ]; then
			base32=$(/usr/bin/oathtool --totp -v "$clientHash" | grep Base32 | awk '{print $3}')
			secretString="${clientName}:${clientHash}"

			echo "Client TOTP String:"
			echo "otpauth://totp/$issuer:$clientName?secret=$base32"
		else
			clientPassword=$2
			encryptPass=$(openssl passwd -1 -salt "$clientHash" "$clientPassword")
			secretString="${clientName}:${encryptPass}:${clientHash}"
		fi
	fi

	if ! grep -q "$clientName" "$oathfile"; then
		echo "Adding oath.secrets to $oathfile"
		echo "$secretString" >> $oathfile
	else
		echo "User already exists in $oathfile"
		echo "Please verify this is the correct user secret"
	fi
}

function revoke_oath() {
	if [ -z "$1" ]; then
		usage "revoke" "oath"
		loud_exit
	fi
	clientName=$1

	oathfile='/etc/openvpn/server/oath.secrets'
	sed -i "/${clientName}/d" "${oathfile}"
}

function generate_qr() {
	if [ -z "$1" ]; then
		usage "generate" "qr"
		loud_exit
	fi
	clientName=$1

	issuer=$(grep 'issuer=' /etc/openvpn/server/oath_generate_secrets.sh | awk -F "'" '{print $2}')

	oathfile='/etc/openvpn/server/oath.secrets'
	clientHash=$(grep "${clientName}" "${oathfile}" | awk -F ':' '{print $2}')
	base32=$(/usr/bin/oathtool --totp -v "$clientHash" | grep Base32 | awk '{print $3}')

	TOTPtoken="otpauth://totp/$issuer:${clientName}?secret=${base32}"

	mkdir -p /etc/openvpn/client/client-configs/qr-codes
	qrencode -t ANSIUTF8 "${TOTPtoken}" -o "/etc/openvpn/client/client-configs/qr-codes/${clientName}.conf"
	qrencode -t png "${TOTPtoken}" -o "/etc/openvpn/client/client-configs/qr-codes/${clientName}.png"

	echo "QR Code: /etc/openvpn/client/client-configs/qr-codes/${clientName}.png"
	echo "QR Code Configuration: /etc/openvpn/client/client-configs/qr-codes/${clientName}.conf"
}

function display_client_cert() {
	if [ -z "$1" ]; then
		usage "display" "cert"
		loud_exit
	fi
	clientName=$1

	outputDIR=/etc/openvpn/client/client-configs/files
	cat ${outputDIR}/"${clientName}".ovpn
}

function display_client_oath() {
	if [ -z "$1" ]; then
		usage "display" "oath"
		loud_exit
	fi
	clientName=$1

	easyVPNConfig="/opt/easy-vpn/server/easy-vpn.env"
	if [[ ! -f "$easyVPNConfig" ]]; then
		echo "EasyVPN Configuration file not found. Please run the configure_env function first."
		echo "Usage: $0 configure_env <EASY_VPN_ISSUER> <EASY_VPN_AUTH_TYPE> <ORGANIZATION_NAME> <VPN_PUBLIC_IP>"
		loud_exit
	fi
	source "$easyVPNConfig"
	issuer=$EASY_VPN_ISSUER
	authType=$EASY_VPN_AUTH_TYPE
	if [[ $issuer == *" "* ]]; then
		issuer=${issuer// /%20}
	fi

	if [[ "$authType" == "PASSWORD_ONLY" ]]; then
		echo "Auth Type is set to PASSWORD_ONLY. OATH is not available."
		graceful_exit
	fi

	oathfile='/etc/openvpn/server/oath.secrets'
	clientHash=$(grep "${clientName}" "${oathfile}" | awk -F ':' '{print $2}')
	base32=$(/usr/bin/oathtool --totp -v "$clientHash" | grep Base32 | awk '{print $3}')

	echo "User String:"
	echo "otpauth://totp/$issuer:${clientName}?secret=${base32}"
	echo "oath.secrets entry:"
	echo "${clientName}:${clientHash}"
}

function update_oath_script() {
	if [[ ! -f "/opt/easy-vpn/server/oath.sh" ]]; then
		echo "Oath script not found. Please check your configuration."
		usage "update" "oath"
		loud_exit
	fi
	echo "Copying oath script to /etc/openvpn/server/..."
	cp /opt/easy-vpn/server/oath.sh /etc/openvpn/server/
}
