# Security Policy

## Supported Versions

| Version | Supported |
|---------|-----------|
| 1.0.0  | ✓ Yes     |

## Reporting a Vulnerability

Please **do not** open a public GitHub issue for security vulnerabilities.

Report security issues directly to the maintainer:

- **Gabe Prudencio**

## Security Considerations for Deployment

### Web UI

- The web UI runs as a **privileged Docker container** with `network_mode: host`. Do not expose port `5000` to the public internet. Place it behind a firewall, restrict access by IP, or tunnel to it via SSH.
- Change `ADMIN_PASSWORD` and `FLASK_SECRET_KEY` in `docker-compose.yml` before starting the container for the first time. Never leave the defaults.
- The admin password is stored in plaintext in a JSON file on the persistent volume (`/opt/easy-vpn/server/web-passwords.json`). This file is chmod `600` and owned by root inside the container.
- There is a single shared admin account. The web UI is not designed for multi-user access.

### VPN Server

- Client certificates are signed by your internal CA. Losing the PKI volume means existing client certificates can never be revoked through normal means — back up your Docker volumes regularly.
- The `crl-verify` directive is enabled in `server-template.conf`, meaning revoked certificates are checked on every connection attempt. Ensure the CRL is regenerated (`easy-vpn revoke cert`) whenever a client is removed.
- `oath.secrets` is stored at `/etc/openvpn/server/oath.secrets` and contains hashed passwords and TOTP seeds. This file is readable by root only. Treat it as a secrets file and include it in your backup strategy.
- The server uses `AES-256-GCM` with `SHA256` for HMAC. The `tls-auth` key provides an additional HMAC firewall against unauthenticated packets.

### Network

- OpenVPN listens on TCP `1194`. If your threat model requires it, change this to a non-standard port in `server-template.conf` and `base-template.conf`.
- IP forwarding is enabled at the OS level as part of the firewall setup step. This is required for VPN routing.
