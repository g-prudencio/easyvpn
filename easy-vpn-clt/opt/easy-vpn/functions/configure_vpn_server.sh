#!/bin/bash
# shellcheck disable=SC1090

function configure_env() {
	if [ -z "$1" ] || [ -z "$2" ] || [ -z "$3" ] || [ -z "$4" ]; then
		echo "One of the require arguments is missing. Please provide them and try again."
		echo "Usage: $0 configure env <EASY_VPN_ISSUER> <EASY_VPN_AUTH_TYPE> <ORGANIZATION_NAME> <VPN_PUBLIC_IP>"
		loud_exit
	fi
	EASY_VPN_ISSUER=$1
	EASY_VPN_AUTH_TYPE=$2
	ORGANIZATION_NAME=$3
	VPN_PUBLIC_IP=$4

	easyVPNConfig="/opt/easy-vpn/server/easy-vpn.env"

	if [[ -f "$easyVPNConfig" ]]; then
		rm -f "$easyVPNConfig"
	fi

	touch "$easyVPNConfig"
	chmod 600 "$easyVPNConfig"

	{
		echo "EASY_VPN_ISSUER=\"$EASY_VPN_ISSUER\""
		echo "EASY_VPN_AUTH_TYPE=\"$EASY_VPN_AUTH_TYPE\""
		echo "ORGANIZATION_NAME=\"$ORGANIZATION_NAME\""
		echo "VPN_PUBLIC_IP=\"$VPN_PUBLIC_IP\""
	} > "$easyVPNConfig"

}

function configure_server() {
	easyVPNConfig="/opt/easy-vpn/server/easy-vpn.env"
	if [[ ! -f "$easyVPNConfig" ]]; then
		echo "EasyVPN Configuration file not found. Please run the configure_env function first."
		echo "Usage: $0 configure env <EASY_VPN_ISSUER> <EASY_VPN_AUTH_TYPE> <ORGANIZATION_NAME> <VPN_PUBLIC_IP>"
		loud_exit
	fi
	source "$easyVPNConfig"

	orgEmail="devteam@$ORGANIZATION_NAME"

	echo "Check that OpenVPN and EasyRSA are installed..."
	openvpn_check=$(dpkg -l | grep -c openvpn)
	easyrsa_check=$(dpkg -l | grep -c easy-rsa)
	if [ "$openvpn_check" -eq 0 ] || [ "$easyrsa_check" -eq 0 ]; then
		echo "OpenVPN and/or EasyRSA are not installed. Installing..."
		apt-get update
		apt-get install -y openvpn easy-rsa
	fi

	echo "Creating EasyRSA Symlink..."
	mkdir -p /opt/easy-vpn/easy-rsa
	ln -s /usr/share/easy-rsa/* /opt/easy-vpn/easy-rsa/
	chown "$USER":"$USER" /opt/easy-vpn/easy-rsa
	chmod 700 /opt/easy-vpn/easy-rsa

	if [ ! -d /etc/openvpn/client/client-configs ]; then
		echo "Creating Client Configuration Directories..."
		mkdir -p /etc/openvpn/client/client-configs/files
		mkdir -p /etc/openvpn/client/client-configs/keys
	fi

	if [ ! -f /opt/easy-vpn/easy-rsa/vars ]; then
		echo "Creating EasyRSA Variables. Be sure to fill in the values..."
		touch /opt/easy-vpn/easy-rsa/vars
	fi

	# If file is empty ask user if they want to use default values and display them
	if [ ! -s /opt/easy-vpn/easy-rsa/vars ]; then
		echo "Vars file is empty. Would you like to use the default values?"
		echo "Default values are:"
		echo "EASYRSA_REQ_COUNTRY     \"US\""
		echo "EASYRSA_REQ_PROVINCE    \"Virginia\""
		echo "EASYRSA_REQ_CITY        \"us-east-1\""
		echo "EASYRSA_REQ_ORG         \"$ORGANIZATION_NAME\""
		echo "EASYRSA_REQ_EMAIL       \"$orgEmail\""
		echo "EASYRSA_REQ_OU          \"Devteam\""
		echo "EASYRSA_ALGO            \"rsa\""
		echo "EASYRSA_DIGEST          \"sha256\""
		read -r -p "Use default values? [Y/n]: " response
		if [[ "$response" =~ ^([yY][eE][sS]|[yY])$ ]] || [[ "$response" == "" ]]; then
			{
				echo "set_var EASYRSA_REQ_COUNTRY     \"US\""
				echo "set_var EASYRSA_REQ_PROVINCE    \"Virginia\""
				echo "set_var EASYRSA_REQ_CITY        \"us-east-1\""
				echo "set_var EASYRSA_REQ_ORG         \"$ORGANIZATION_NAME\""
				echo "set_var EASYRSA_REQ_EMAIL       \"$orgEmail\""
				echo "set_var EASYRSA_REQ_OU          \"Devteam\""
				echo "set_var EASYRSA_ALGO            \"rsa\""
				echo "set_var EASYRSA_DIGEST          \"sha256\""
			} > /opt/easy-vpn/easy-rsa/vars

		elif [[ "$response" =~ ^([nN][oO]|[nN])$ ]]; then
			read -r -p "Would you like to configure vars file now? [Y/n]: " manual_response
			if [[ "$manual_response" =~ ^([yY][eE][sS]|[yY])$ ]] || [[ "$response" == "" ]]; then
				read -r -p "Enter the country code: " country
				read -r -p "Enter the province: " province
				read -r -p "Enter the city: " city
				read -r -p "Enter the organization name: " orgName
				read -r -p "Enter the email: " orgEmail
				read -r -p "Enter the organizational unit: " orgUnit
				read -r -p "Enter the algorithm: " algo
				read -r -p "Enter the digest: " digest
				extra_config=""
				while true; do
					read -r -p "Enter further configs or 'done' to finish (be sure to enter the full config, ex. set_var EASYRSA_CRL_DAY	2650): " config
					if [[ "$config" == "done" ]]; then
						break
					fi
					extra_config+="\n$config"
				done
			else
				echo "Please manually configure the vars file before continuing."
				loud_exit
			fi

			{
				echo "set_var EASYRSA_REQ_COUNTRY     \"$country\""
				echo "set_var EASYRSA_REQ_PROVINCE    \"$province\""
				echo "set_var EASYRSA_REQ_CITY        \"$city\""
				echo "set_var EASYRSA_REQ_ORG         \"$orgName\""
				echo "set_var EASYRSA_REQ_EMAIL       \"$orgEmail\""
				echo "set_var EASYRSA_REQ_OU          \"$orgUnit\""
				echo "set_var EASYRSA_ALGO            \"$algo\""
				echo "set_var EASYRSA_DIGEST          \"$digest\""
				echo -e "$extra_config"
			} > /opt/easy-vpn/easy-rsa/vars

		else
			echo "Invalid response. Please try again."
			loud_exit
		fi
	fi

	echo "Initializing EasyRSA PKI..."
	cd /opt/easy-vpn/easy-rsa || { echo "Directory Not Found"; loud_exit; }
	./easyrsa init-pki

	echo "Creating Server Certificates..."
	./easyrsa gen-req server nopass

	echo "Copying Key to OpenVPN Server directory..."
	cp ./pki/private/server.key /etc/openvpn/server/

	echo "Building CA..."
	./easyrsa build-ca nopass

	echo "Copying CA Certificates to OpenVPN Client and Server directory..."
	cp ./pki/ca.crt /etc/openvpn/client/client-configs/keys
	cp ./pki/ca.crt /etc/openvpn/server/

	echo "Signing Server Certificates..."
	./easyrsa sign-req server server

	echo "Copying Server Certificates to OpenVPN Server directory..."
	cp ./pki/issued/server.crt /etc/openvpn/server/

	echo "Creating TLS_Crypt Key..."
	openvpn --genkey secret /etc/openvpn/server/ta.key
	cp /etc/openvpn/server/ta.key /etc/openvpn/client/client-configs/keys

	echo "Creating Diffie-Hellman Key Exchange..."
	./easyrsa gen-dh

	echo "Copying DH Key to OpenVPN Server directory..."
	cp ./pki/dh.pem /etc/openvpn/server/

	echo "Copying server-template.conf to /etc/openvpn/server/server.conf..."
	cp /opt/easy-vpn/server/server-template.conf /etc/openvpn/server/server.conf

	echo "Copying oath script to /etc/openvpn/server/..."
	cp /opt/easy-vpn/server/oath.sh /etc/openvpn/server/

	echo "Copying over base client configuration..."
	cp /opt/easy-vpn/client/base-template.conf /etc/openvpn/client/client-configs/base.conf
	sed -i "s/REPLACE_WITH_VPN_PUBLIC_IP/$VPN_PUBLIC_IP/g" /etc/openvpn/client/client-configs/base.conf

	echo "Copying over Client Connection Logging Scripts..."
	cp /opt/easy-vpn/server/log_client_connect.sh /etc/openvpn/server/
	cp /opt/easy-vpn/server/log_client_disconnect.sh /etc/openvpn/server/
	touch /var/log/openvpn/client_connections.log
	chmod 777 /var/log/openvpn/client_connections.log

	echo "Starting OpenVPN Server..."
	systemctl -f enable openvpn-server@server.service
	systemctl start openvpn-server@server.service
}