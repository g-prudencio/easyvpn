# EasyVPN

A command-line tool and web management interface for deploying and managing an OpenVPN server with EasyRSA PKI and optional TOTP multi-factor authentication.

---

## Overview

EasyVPN consists of two components:

- **`easy-vpn-clt/`** — A Debian package containing the `easy-vpn` CLI tool. Once installed it lives at `/usr/bin/easy-vpn` and wraps OpenVPN, EasyRSA, and oathtool into a single set of commands for managing a VPN server and its clients.
- **`easy-vpn-web/`** — A Flask web application that runs in Docker and provides a browser-based UI for all the same operations. This is the recommended way to manage the server after initial setup.

---

## Repository Structure

```
.
├── README.md
├── build_and_install_easyVPN.sh        # Build and install the .deb package manually
│
├── easy-vpn-clt/                       # Debian package source
│   ├── DEBIAN/
│   │   ├── control                     # Package metadata and dependencies
│   │   └── postinst                    # Post-install script
│   ├── opt/easy-vpn/
│   │   ├── client/
│   │   │   └── base-template.conf      # Base OpenVPN client config template
│   │   ├── functions/
│   │   │   ├── configure_vpn_server.sh # Server setup logic
│   │   │   ├── help_and_exit.sh        # Help, logging, and exit helpers
│   │   │   └── openvpn_functions.sh    # Client cert, OATH, QR, and status functions
│   │   └── server/
│   │       ├── log_client_connect.sh   # Logs client connections (called by OpenVPN)
│   │       ├── log_client_disconnect.sh
│   │       ├── oath_generate_secrets.sh # Generates TOTP secrets — edit issuer here
│   │       ├── oath.sh                 # OpenVPN auth-user-pass-verify script
│   │       └── server-template.conf    # OpenVPN server config template
│   └── usr/
│       ├── bin/
│       │   └── easy-vpn                # Main CLI entry point
│       └── share/
│           ├── doc/easy-vpn/
│           │   ├── changelog
│           │   └── copyright
│           └── man/man8/
│               └── easy-vpn.8          # Man page
│
└── easy-vpn-web/                       # Docker web management UI
    ├── app.py                          # Flask application
    ├── Dockerfile
    ├── docker-compose.yml
    ├── requirements.txt                # Flask + gunicorn
    ├── firewall_setup.sh               # Manual firewall fallback script
    ├── templates/
    │   ├── base.html
    │   ├── login.html
    │   ├── dashboard.html
    │   ├── configure.html
    │   ├── clients.html
    │   └── status.html
    └── static/                         # Reserved for future CSS/JS assets
```

---

## Prerequisites

- A Linux server (Debian/Ubuntu recommended) with Docker and Docker Compose installed
- The server must have a public IP address or hostname reachable by VPN clients
- Port `1194/tcp` open on your host firewall/security group
- Port `5000/tcp` accessible from wherever you want to manage the VPN

---

## Quick Start

**1. Clone the repo and set your credentials**

```bash
git clone <your-repo-url>
cd <repo-root>
```

Open `easy-vpn-web/docker-compose.yml` and change the two environment variables before doing anything else:

```yaml
environment:
  - FLASK_SECRET_KEY=replace-with-a-long-random-string
  - ADMIN_PASSWORD=replace-with-a-strong-password
```

**2. Start the web app**

```bash
cd easy-vpn-web
docker compose up -d
```

The first build will take a few minutes as Docker downloads the base image and installs all dependencies. Subsequent starts are instant.

**3. Open the web UI and complete setup**

Navigate to `http://<your-server-ip>:5000` and log in. Then complete the three setup steps on the **Configure** page in order:

| Step | What it does |
|------|-------------|
| **Step 1 — Environment** | Sets your issuer name, auth type, organization, and public IP |
| **Step 2 — Initialize Server** | Generates the PKI, signs certificates, creates TLS keys, starts OpenVPN. Takes 1–3 minutes. Run once only. |
| **Step 3 — Firewall** | Enables IP forwarding and sets up iptables NAT rules so VPN clients can reach the internet |

Once all three steps show a green ✓, go to **Clients** to create your first VPN user.

---

## Auth Types

The `EASY_VPN_AUTH_TYPE` setting controls how clients authenticate when connecting:

| Value | Behavior |
|-------|----------|
| `TOTP_ONLY` | Client enters a 6-digit TOTP code only (no password) |
| `PASSWORD_ONLY` | Client enters a static password only |
| `BOTH` | Client must enter `password:TOTPcode` — both are required |
| `TOTP_OR_PASSWORD` | Client can use either a TOTP code or a password |

---

## Managing Clients

All client management is done through the **Clients** page in the web UI.

**Creating a client** — Enter a name (alphanumeric, dashes, underscores only), choose whether to generate a TOTP secret, and optionally set a password. The app will generate and display the `.ovpn` certificate file.

**Distributing the certificate** — Click **View .ovpn** next to any client to view or download their certificate file. This file is everything the client needs to import into their OpenVPN app.

**TOTP setup** — Click **View TOTP** to get the `otpauth://` URI, or **Show QR** to display a QR code the client can scan directly into Google Authenticator, Authy, or any compatible app.

**Revoking access** — Click **Revoke** to remove a client. You can revoke just their TOTP secret (they can still connect with a new one) or revoke their certificate entirely (they cannot connect at all).

---

## CLI Reference

The `easy-vpn` binary is available inside the Docker container or directly on the host if the `.deb` package is installed. All operations are also accessible through the web UI.

```
easy-vpn configure env  <issuer> <auth_type> <org_name> <public_ip>
easy-vpn configure server

easy-vpn create  <client-name> <generate_oath> [client-password]
easy-vpn display cert  <client-name>
easy-vpn display oath  <client-name>

easy-vpn generate oath  <client-name> [client-password]
easy-vpn generate qr    <client-name>

easy-vpn revoke cert  <client-name>
easy-vpn revoke oath  <client-name>

easy-vpn list
easy-vpn status expired
easy-vpn status unused  [auto-revoke]

easy-vpn update oath
easy-vpn version
easy-vpn help
```

---

## Building the .deb Package

If you need to install the CLI on a host directly (without Docker), use the build script:

```bash
# Build the package
./build_and_install_easyVPN.sh build

# Install it
./build_and_install_easyVPN.sh install

# Build and install in one step
./build_and_install_easyVPN.sh build-install
```

This produces `easy-vpn.deb` in the repo root and installs it with `dpkg`.

---

## Data Persistence

The Docker setup uses named volumes to persist all VPN state outside the container. This means your PKI, certificates, and client configs survive container rebuilds and updates.

| Volume | Path in container | Contains |
|--------|-------------------|----------|
| `openvpn_config` | `/etc/openvpn` | Server config, certs, TLS key, client ovpn files |
| `openvpn_logs` | `/var/log/openvpn` | Connection logs, status file |
| `easyrsa_pki` | `/opt/easy-vpn` | EasyRSA PKI, index, CRL, OATH secrets |

> **Important:** Back up your volumes before any major changes. The PKI in particular cannot be regenerated — losing it means revoking all existing client certificates.

---

## Logs

| Log file | Contents |
|----------|----------|
| `/var/log/openvpn/openvpn.log` | OpenVPN daemon output |
| `/var/log/openvpn/openvpn-status.log` | Live connection status, updated every minute |
| `/var/log/openvpn/client_connections.log` | Per-client connect/disconnect timestamps |
| `/var/log/openvpn/easy-vpn.log` | easy-vpn CLI audit log |

To tail logs from outside the container:

```bash
docker exec easy-vpn-web tail -f /var/log/openvpn/openvpn.log
docker exec easy-vpn-web tail -f /var/log/openvpn/client_connections.log
```

---

## Configuration Files

**`oath_generate_secrets.sh`** — Edit the `issuer=` line at the top of this file to set the name that appears in your authenticator app. The value should be URL-encoded (spaces as `%20`). This file is deployed to `/etc/openvpn/server/` during Step 2.

**`server-template.conf`** — The OpenVPN server configuration. Deployed to `/etc/openvpn/server/server.conf` during Step 2. Key settings:
- `port 1194` / `proto tcp` — Change if needed, but update firewall rules and client template to match
- `server 10.8.0.0 255.255.255.0` — VPN subnet assigned to clients
- `reneg-sec 3600` — Data channel renegotiation interval

**`base-template.conf`** — The base OpenVPN client configuration. The server's public IP is substituted in during Step 2.

---

## Updating

To update the web app after making code changes:

```bash
cd easy-vpn-web
docker compose down
docker compose up -d --build
```

Your PKI and client data are safe — they live in Docker volumes, not the container image.

---

## Known Limitations

- The web UI uses a single shared admin password. It is not designed for multi-user access.
- The web app must run as a privileged container (`privileged: true`) because it needs to manage OpenVPN, apply iptables rules, and access the tun interface. Do not expose port 5000 to the public internet — place it behind a firewall or VPN.
- Firewall rules applied through the web UI (Step 3) are written to `/etc/iptables/rules.v4` inside the container. Because the container uses `network_mode: host`, these rules apply to the host directly and persist across container restarts. They will not survive a full server reboot unless `iptables-restore` is configured on the host.

---

## Security

See [SECURITY.md](SECURITY.md) for the vulnerability reporting policy and a full list of security considerations for deployment.

---

## Authors

**Gabe Prudencio**

See [CONTRIBUTORS](CONTRIBUTORS) for full contributor details.
