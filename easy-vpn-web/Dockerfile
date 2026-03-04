FROM debian:bookworm-slim

ENV DEBIAN_FRONTEND=noninteractive

# System packages
RUN apt-get update && apt-get install -y --no-install-recommends \
    python3 python3-pip python3-venv \
    openvpn easy-rsa \
    oathtool qrencode \
    openssl curl ca-certificates \
    iptables iproute2 procps \
    && rm -rf /var/lib/apt/lists/*

# ── Install easy-vpn files from the sibling easy-vpn-clt/ folder.
# docker-compose sets the build context to the project root (the folder
# containing both easy-vpn-clt/ and easy-vpn-web/) so these paths work.
COPY easy-vpn-clt/usr/bin/easy-vpn           /usr/bin/easy-vpn
COPY easy-vpn-clt/opt/easy-vpn/         /opt/easy-vpn/
RUN chmod +x /usr/bin/easy-vpn

# ── Python virtualenv — installs Flask AND gunicorn from requirements.txt
WORKDIR /app
COPY easy-vpn-web/requirements.txt .
RUN python3 -m venv /venv && /venv/bin/pip install --no-cache-dir -r requirements.txt

# ── Copy the web app
COPY easy-vpn-web/app.py        .
COPY easy-vpn-web/templates/    ./templates/
COPY easy-vpn-web/static/       ./static/

ENV PATH="/venv/bin:$PATH"
# These are defaults — override them in docker-compose.yml
ENV SECRET_KEY="change-me-in-production"
ENV ADMIN_PASSWORD="admin"

EXPOSE 5000

# Pre-create all directories that OpenVPN and EasyRSA expect to exist
RUN mkdir -p \
    /var/log/openvpn \
    /etc/openvpn/server \
    /etc/openvpn/client/client-configs/files \
    /etc/openvpn/client/client-configs/keys \
    /etc/openvpn/client/client-configs/qr-codes \
    /opt/easy-vpn/server \
    /opt/easy-vpn/easy-rsa \
  && touch /var/log/openvpn/client_connections.log \
  && chmod 777 /var/log/openvpn/client_connections.log

# gunicorn is installed by the venv step above — no separate install needed
CMD ["gunicorn", "--bind", "0.0.0.0:5000", "--workers", "2", "--timeout", "300", "app:app"]
