#!/bin/bash
# firewall_setup.sh
# Sets up iptables NAT masquerade and enables IP forwarding for OpenVPN.
# Run ONCE after server setup, or add to systemd/cron for persistence.
# shellcheck disable=SC2181

set -e

# ── 1. Enable IP forwarding ────────────────────────────────────────────────────
echo "Enabling IP forwarding..."
if ! grep -q "^net.ipv4.ip_forward=1" /etc/sysctl.conf; then
    echo "net.ipv4.ip_forward=1" >> /etc/sysctl.conf
fi
sysctl -p /etc/sysctl.conf

# ── 2. Detect primary network interface ───────────────────────────────────────
NIC=$(ip route get 8.8.8.8 | awk '{print $5; exit}')
echo "Detected primary NIC: ${NIC}"

# ── 3. iptables NAT masquerade (allows VPN clients to reach the internet) ─────
echo "Adding NAT masquerade rule..."
iptables -t nat -C POSTROUTING -s 10.8.0.0/24 -o "${NIC}" -j MASQUERADE 2>/dev/null \
    || iptables -t nat -A POSTROUTING -s 10.8.0.0/24 -o "${NIC}" -j MASQUERADE

# ── 4. Allow forwarding between tun0 and primary NIC ─────────────────────────
echo "Allowing FORWARD traffic..."
iptables -C FORWARD -i tun0 -o "${NIC}" -j ACCEPT 2>/dev/null \
    || iptables -A FORWARD -i tun0 -o "${NIC}" -j ACCEPT

iptables -C FORWARD -i "${NIC}" -o tun0 -m state --state RELATED,ESTABLISHED -j ACCEPT 2>/dev/null \
    || iptables -A FORWARD -i "${NIC}" -o tun0 -m state --state RELATED,ESTABLISHED -j ACCEPT

# ── 5. Allow OpenVPN port (TCP 1194) ──────────────────────────────────────────
echo "Opening TCP port 1194 for OpenVPN..."
iptables -C INPUT -p tcp --dport 1194 -j ACCEPT 2>/dev/null \
    || iptables -A INPUT -p tcp --dport 1194 -j ACCEPT

# ── 6. Persist rules across reboots ──────────────────────────────────────────
echo "Persisting iptables rules..."
if command -v netfilter-persistent &>/dev/null; then
    netfilter-persistent save
elif command -v iptables-save &>/dev/null; then
    iptables-save > /etc/iptables/rules.v4 2>/dev/null || iptables-save > /etc/iptables.rules
fi

echo ""
echo "✔ Firewall configured:"
echo "  • IP forwarding: ON"
echo "  • NAT masquerade: 10.8.0.0/24 → ${NIC}"
echo "  • FORWARD rules: tun0 ↔ ${NIC}"
echo "  • OpenVPN port 1194/tcp: OPEN"
