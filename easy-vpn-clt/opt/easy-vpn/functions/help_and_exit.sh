#!/bin/bash

function graceful_exit() {
	exit 0
}

function help() {
	echo "Usage: easy-vpn <command> [options]"
	echo ""
	echo "Commands:"
	echo "  help"
	echo "  configure <issuer> <orgName> <orgEmail> <VPN_PUBLIC_IP>"
	echo "  create <client-name> <GENERATE_OATH>"
	echo "  revoke <client-name>"
	echo "  list"
	echo "  expire_status"
	echo "  use_status <auto-revoke>"
	echo "	generate_oath <clientName>"
	echo "	revoke_oath <clientName>"
	echo "	generate_qr <client-name>"
	echo "	display <clientName>"
	echo "  version"
	echo ""
	graceful_exit
}

function log() {
	log_type=$1
	message=$2

	log_dir="/var/log/openvpn/easy-vpn.log"
	if [[ ! -f "$log_dir" ]]; then
		touch "$log_dir"
		chmod 600 "$log_dir"
	fi
	echo "[$(date +"%Y-%m-%dT%H:%M:%S%z")][$log_type]: $message" >> "$log_dir"
}

function loud_exit() {
	exit 1
}

function unknown_command() {
	echo "Unknown command: $1"
	echo "Use 'easy-vpn help' for a list of available commands"
	loud_exit
}

function usage() {
	action=$1
	if [[ "$action" == "configure" ]]; then
		subAction=$2
		if [[ -z "$subAction" ]]; then
			echo "Usage: $0 configure <env|server>"
		fi
		if [[ "$subAction" == "env" ]]; then
			echo "Usage: $0 configure env <EASY_VPN_ISSUER> <EASY_VPN_AUTH_TYPE> <ORGANIZATION_NAME> <VPN_PUBLIC_IP>"
		fi
		if [[ "$subAction" == "server" ]]; then
			echo "Usage: $0 configure server"
		fi
	fi
	if [[ "$action" == "create" ]]; then
		echo "Usage: $0 create <client-name> <GENERATE_OATH> <client-password>"
	fi
	if [[ "$action" == "display" ]]; then
		subAction=$2
		if [[ -z "$subAction" ]]; then
			echo "Usage: $0 display <cert|oath> <client-name>"
		fi
		if [[ "$subAction" == "cert" ]]; then
			echo "Usage: $0 display cert <client-name>"
		fi
		if [[ "$subAction" == "oath" ]]; then
			echo "Usage: $0 display oath <client-name>"
		fi
	fi
	if [[ "$action" == "generate" ]]; then
		subAction=$2
		if [[ -z "$subAction" ]]; then
			echo "Usage: $0 generate <oath|qr> <client-name>"
		fi
		if [[ "$subAction" == "oath" ]]; then
			echo "Usage: $0 generate oath <client-name>"
		fi
		if [[ "$subAction" == "qr" ]]; then
			echo "Usage: $0 generate qr <client-name>"
		fi
	fi
	if [[ "$action" == "list" ]]; then
		echo "Usage: $0 list"
	fi
	if [[ "$action" == "revoke" ]]; then
		subAction=$2
		if [[ -z "$subAction" ]]; then
			echo "Usage: $0 revoke <cert|oath> <client-name>"
		fi
		if [[ "$subAction" == "cert" ]]; then
			echo "Usage: $0 revoke cert <client-name>"
		fi
		if [[ "$subAction" == "oath" ]]; then
			echo "Usage: $0 revoke oath <client-name>"
		fi
	fi
	if [[ "$action" == "status" ]]; then
		subAction=$2
		if [[ -z "$subAction" ]]; then
			echo "Usage: $0 status <expired|unused>"
		fi
		if [[ "$subAction" == "expired" ]]; then
			echo "Usage: $0 status expired"
		fi
		if [[ "$subAction" == "unused" ]]; then
			echo "Usage: $0 status used <auto-revoke>"
		fi
	fi
	if [[ "$action" == "update" ]]; then
		echo "Usage: $0 update oath"
	fi
}

function version() {
	version=$(dpkg -s easy-vpn | grep '^Version:')
	echo "/usr/bin/easy-vpn $version"
}
