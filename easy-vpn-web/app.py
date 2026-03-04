#!/usr/bin/env python3
"""EasyVPN Web Manager — Flask Application"""

import subprocess, os, re, base64, shutil
from functools import wraps
from flask import Flask, render_template, request, jsonify, session, redirect, url_for, flash

app = Flask(__name__)
app.secret_key = os.environ.get("SECRET_KEY", "change-me-in-production")
ADMIN_PASSWORD = os.environ.get("ADMIN_PASSWORD", "admin")
EASY_VPN_BIN = "/usr/bin/easy-vpn"


# ── Helpers ────────────────────────────────────────────────────────────────

def run_cmd(cmd: list, timeout: int = 180) -> dict:
    try:
        r = subprocess.run(cmd, capture_output=True, text=True, timeout=timeout)
        return {"stdout": r.stdout.strip(), "stderr": r.stderr.strip(),
                "returncode": r.returncode, "success": r.returncode == 0}
    except subprocess.TimeoutExpired:
        return {"stdout": "", "stderr": "Command timed out", "returncode": -1, "success": False}
    except Exception as e:
        return {"stdout": "", "stderr": str(e), "returncode": -1, "success": False}


def sanitize(name: str) -> str:
    return re.sub(r"[^a-zA-Z0-9_\-]", "", name)


def is_configured() -> bool:
    return os.path.isfile("/opt/easy-vpn/server/easy-vpn.env")


def is_server_initialized() -> bool:
    """True once PKI has been built (ca.crt exists in the openvpn server dir)."""
    return os.path.isfile("/etc/openvpn/server/ca.crt")


def is_firewall_configured() -> bool:
    """Check whether our NAT masquerade rule is already present."""
    r = subprocess.run(
        ["iptables", "-t", "nat", "-C", "POSTROUTING", "-s", "10.8.0.0/24", "-j", "MASQUERADE"],
        capture_output=True
    )
    return r.returncode == 0


def read_env() -> dict:
    env, path = {}, "/opt/easy-vpn/server/easy-vpn.env"
    if not os.path.isfile(path):
        return env
    with open(path) as f:
        for line in f:
            if "=" in line:
                k, _, v = line.strip().partition("=")
                env[k.strip()] = v.strip().strip('"')
    return env


def login_required(f):
    @wraps(f)
    def decorated(*args, **kwargs):
        if not session.get("authenticated"):
            return redirect(url_for("login"))
        return f(*args, **kwargs)
    return decorated


# ── Auth ───────────────────────────────────────────────────────────────────

@app.route("/login", methods=["GET", "POST"])
def login():
    if request.method == "POST":
        if request.form.get("password") == ADMIN_PASSWORD:
            session["authenticated"] = True
            return redirect(url_for("dashboard"))
        flash("Invalid password.", "error")
    return render_template("login.html")


@app.route("/logout")
def logout():
    session.clear()
    return redirect(url_for("login"))


# ── Dashboard ──────────────────────────────────────────────────────────────

@app.route("/")
@login_required
def dashboard():
    configured = is_configured()
    env = read_env() if configured else {}
    clients = []
    if configured:
        r = run_cmd([EASY_VPN_BIN, "list"])
        if r["success"] and r["stdout"]:
            clients = [c.strip() for c in r["stdout"].splitlines() if c.strip()]
    return render_template(
        "dashboard.html",
        configured=configured,
        server_initialized=is_server_initialized(),
        firewall_configured=is_firewall_configured(),
        env=env,
        clients=clients
    )


# ── Configure ──────────────────────────────────────────────────────────────

@app.route("/configure", methods=["GET", "POST"])
@login_required
def configure():
    if request.method == "POST":
        action = request.form.get("action")

        if action == "env":
            fields = ["issuer", "auth_type", "org_name", "public_ip"]
            vals = [request.form.get(f, "").strip() for f in fields]
            if not all(vals):
                return jsonify({"success": False, "message": "All fields required."})
            return jsonify(run_cmd([EASY_VPN_BIN, "configure", "env", *vals]))

        if action == "server":
            return jsonify(run_cmd([EASY_VPN_BIN, "configure", "server"], timeout=600))

        if action == "firewall":
            return jsonify(_run_firewall_setup())

    return render_template(
        "configure.html",
        configured=is_configured(),
        server_initialized=is_server_initialized(),
        firewall_configured=is_firewall_configured(),
        env=read_env()
    )


def _run_firewall_setup() -> dict:
    """
    Apply iptables NAT masquerade + FORWARD rules + enable IP forwarding.
    Equivalent to firewall_setup.sh but executed directly from Python so
    the user never has to SSH in.
    """
    log = []
    try:
        # 1. Enable IP forwarding
        with open("/proc/sys/net/ipv4/ip_forward", "w") as f:
            f.write("1\n")

        # Persist across reboots via sysctl.conf
        sysctl_path = "/etc/sysctl.conf"
        with open(sysctl_path) as f:
            content = f.read()
        if "net.ipv4.ip_forward=1" not in content:
            with open(sysctl_path, "a") as f:
                f.write("\nnet.ipv4.ip_forward=1\n")
        log.append("✔ IP forwarding enabled")

        # 2. Detect primary NIC
        r = subprocess.run(
            ["ip", "route", "get", "8.8.8.8"],
            capture_output=True, text=True
        )
        nic = None
        for part in r.stdout.split():
            if part == "dev":
                nic = r.stdout.split()[r.stdout.split().index("dev") + 1]
                break
        if not nic:
            return {"success": False, "stdout": "\n".join(log),
                    "stderr": "Could not detect primary network interface"}
        log.append(f"✔ Detected primary NIC: {nic}")

        # 3. NAT masquerade — add only if not already present
        check = subprocess.run(
            ["iptables", "-t", "nat", "-C", "POSTROUTING",
             "-s", "10.8.0.0/24", "-o", nic, "-j", "MASQUERADE"],
            capture_output=True
        )
        if check.returncode != 0:
            subprocess.run(
                ["iptables", "-t", "nat", "-A", "POSTROUTING",
                 "-s", "10.8.0.0/24", "-o", nic, "-j", "MASQUERADE"],
                check=True
            )
        log.append("✔ NAT masquerade rule applied")

        # 4. FORWARD rules
        for rule in [
            ["iptables", "-C", "FORWARD", "-i", "tun0", "-o", nic, "-j", "ACCEPT"],
            ["iptables", "-C", "FORWARD", "-i", nic, "-o", "tun0",
             "-m", "state", "--state", "RELATED,ESTABLISHED", "-j", "ACCEPT"],
        ]:
            check = subprocess.run(rule, capture_output=True)
            if check.returncode != 0:
                add = rule.copy()
                add[1] = "-A"
                subprocess.run(add, check=True)
        log.append("✔ FORWARD rules applied")

        # 5. Open port 1194
        check = subprocess.run(
            ["iptables", "-C", "INPUT", "-p", "tcp", "--dport", "1194", "-j", "ACCEPT"],
            capture_output=True
        )
        if check.returncode != 0:
            subprocess.run(
                ["iptables", "-A", "INPUT", "-p", "tcp", "--dport", "1194", "-j", "ACCEPT"],
                check=True
            )
        log.append("✔ Port 1194/tcp opened")

        # 6. Persist rules if iptables-save is available
        if shutil.which("iptables-save"):
            os.makedirs("/etc/iptables", exist_ok=True)
            with open("/etc/iptables/rules.v4", "w") as f:
                subprocess.run(["iptables-save"], stdout=f, check=True)
            log.append("✔ Rules persisted to /etc/iptables/rules.v4")
        else:
            log.append("⚠ iptables-save not found — rules will not survive a reboot")

        return {"success": True, "stdout": "\n".join(log), "stderr": "", "returncode": 0}

    except Exception as e:
        log.append(f"✘ Error: {e}")
        return {"success": False, "stdout": "\n".join(log), "stderr": str(e), "returncode": 1}


# ── Clients ────────────────────────────────────────────────────────────────

@app.route("/clients")
@login_required
def clients():
    if not is_configured():
        flash("Configure the VPN server first.", "warning")
        return redirect(url_for("configure"))
    r = run_cmd([EASY_VPN_BIN, "list"])
    client_list = [c.strip() for c in r["stdout"].splitlines() if c.strip()] if r["success"] else []
    return render_template("clients.html", clients=client_list, env=read_env())


@app.route("/clients/create", methods=["POST"])
@login_required
def create_client():
    name = sanitize(request.form.get("client_name", ""))
    gen_oath = request.form.get("generate_oath", "false")
    password = request.form.get("client_password", "nopass")
    if not name:
        return jsonify({"success": False, "message": "Invalid client name."})
    cmd = [EASY_VPN_BIN, "create", name, gen_oath]
    if password and password != "nopass":
        cmd.append(password)
    return jsonify(run_cmd(cmd, timeout=180))


@app.route("/clients/<client_name>/cert")
@login_required
def display_cert(client_name):
    return jsonify(run_cmd([EASY_VPN_BIN, "display", "cert", sanitize(client_name)]))


@app.route("/clients/<client_name>/oath")
@login_required
def display_oath(client_name):
    env = read_env()
    if env.get("EASY_VPN_AUTH_TYPE") == "PASSWORD_ONLY":
        return jsonify({"success": False, "message": "Auth type is PASSWORD_ONLY — no TOTP."})
    return jsonify(run_cmd([EASY_VPN_BIN, "display", "oath", sanitize(client_name)]))


@app.route("/clients/<client_name>/qr")
@login_required
def generate_qr(client_name):
    name = sanitize(client_name)
    res = run_cmd([EASY_VPN_BIN, "generate", "qr", name])
    qr_b64 = None
    png = f"/etc/openvpn/client/client-configs/qr-codes/{name}.png"
    if os.path.isfile(png):
        with open(png, "rb") as f:
            qr_b64 = base64.b64encode(f.read()).decode()
    return jsonify({**res, "qr_b64": qr_b64})


@app.route("/clients/<client_name>/revoke", methods=["POST"])
@login_required
def revoke_client(client_name):
    name = sanitize(client_name)
    rtype = request.form.get("type", "cert")
    if rtype not in ("cert", "oath"):
        return jsonify({"success": False, "message": "Invalid revoke type."})
    return jsonify(run_cmd([EASY_VPN_BIN, "revoke", rtype, name]))


# ── Status ─────────────────────────────────────────────────────────────────

@app.route("/status")
@login_required
def status():
    if not is_configured():
        flash("Configure the VPN server first.", "warning")
        return redirect(url_for("configure"))
    return render_template("status.html")


@app.route("/api/status/expired")
@login_required
def api_expired():
    return jsonify(run_cmd([EASY_VPN_BIN, "status", "expired"]))


@app.route("/api/status/unused")
@login_required
def api_unused():
    auto = request.args.get("auto_revoke", "false")
    return jsonify(run_cmd([EASY_VPN_BIN, "status", "unused", auto]))


@app.route("/api/openvpn/running")
@login_required
def api_running():
    r = run_cmd(["systemctl", "is-active", "openvpn-server@server.service"])
    return jsonify({"active": r["stdout"] == "active", "status": r["stdout"]})


@app.route("/api/version")
@login_required
def api_version():
    return jsonify(run_cmd([EASY_VPN_BIN, "version"]))


if __name__ == "__main__":
    app.run(host="0.0.0.0", port=5000, debug=False)
