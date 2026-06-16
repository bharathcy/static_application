#!/usr/bin/env bash
#
# setup_ssl_certbot.sh — Obtain a Let's Encrypt certificate via Certbot
# *standalone* mode and wire it into an existing Nginx server block.
#
# Because standalone validation needs port 80, the script stops Nginx,
# issues the certificate, restarts Nginx, then updates the site's config
# to serve HTTPS (with an HTTP->HTTPS redirect).
#
# Usage:
#   sudo ./setup_ssl_certbot.sh [-d DOMAIN] [-e EMAIL] [-b BACKEND_PORT] [-s] [-y]
#
# Options:
#   -d DOMAIN         Domain to secure (e.g. example.com)
#   -e EMAIL          Contact email for Let's Encrypt (renewal notices)
#   -b BACKEND_PORT   Local app port to proxy_pass to       (default: 3000)
#   -s                Use the Let's Encrypt staging server (test, untrusted)
#   -y                Non-interactive; require args, no prompts
#   -h                Show this help
#
# Anything not given on the command line is prompted for, unless -y is set.
#
set -euo pipefail

# --- Pretty logging -------------------------------------------------------
log()  { printf '\033[1;32m[+]\033[0m %s\n' "$*"; }
warn() { printf '\033[1;33m[!]\033[0m %s\n' "$*"; }
err()  { printf '\033[1;31m[-]\033[0m %s\n' "$*" >&2; }

usage() { sed -n '2,21p' "$0" | sed 's/^# \{0,1\}//'; exit "${1:-0}"; }

# --- Defaults & arg parsing ----------------------------------------------
DOMAIN=""
EMAIL=""
BACKEND_PORT=""
STAGING=0
ASSUME_YES=0

while getopts ":d:e:b:syh" opt; do
    case "$opt" in
        d) DOMAIN="$OPTARG" ;;
        e) EMAIL="$OPTARG" ;;
        b) BACKEND_PORT="$OPTARG" ;;
        s) STAGING=1 ;;
        y) ASSUME_YES=1 ;;
        h) usage 0 ;;
        :) err "Option -$OPTARG requires an argument."; usage 1 ;;
        \?) err "Unknown option: -$OPTARG"; usage 1 ;;
    esac
done

# --- Pre-flight check -----------------------------------------------------
if [[ "$(id -u)" -ne 0 ]]; then
    err "This script must be run as root. Try: sudo $0"
    exit 1
fi

# --- Helpers --------------------------------------------------------------
is_valid_port()   { [[ "$1" =~ ^[0-9]+$ ]] && (( $1 >= 1 && $1 <= 65535 )); }
is_valid_domain() { [[ "$1" =~ ^[A-Za-z0-9.-]+\.[A-Za-z]{2,}$ ]]; }
is_valid_email()  { [[ "$1" =~ ^[^@[:space:]]+@[^@[:space:]]+\.[^@[:space:]]+$ ]]; }

prompt_default() {            # prompt_default <varname> <message> <default>
    local __var="$1" __msg="$2" __def="$3" __input
    read -r -p "$__msg [$__def]: " __input
    printf -v "$__var" '%s' "${__input:-$__def}"
}

require_or_prompt() {         # require_or_prompt <varname> <message> <validator>
    local __var="$1" __msg="$2" __validate="$3" __val
    __val="${!__var}"
    if [[ -z "$__val" ]]; then
        if [[ "$ASSUME_YES" -eq 1 ]]; then
            err "$__msg is required in non-interactive mode."
            exit 1
        fi
        while :; do
            read -r -p "$__msg: " __val
            "$__validate" "$__val" && break
            warn "Invalid value, try again."
        done
        printf -v "$__var" '%s' "$__val"
    fi
}

# --- Resolve configuration values ----------------------------------------
require_or_prompt DOMAIN "Domain to secure (e.g. example.com)" is_valid_domain
require_or_prompt EMAIL  "Contact email for Let's Encrypt"     is_valid_email

if [[ -z "$BACKEND_PORT" ]]; then
    if [[ "$ASSUME_YES" -eq 1 ]]; then BACKEND_PORT=3000
    else prompt_default BACKEND_PORT "Local backend/app port to proxy to" 3000; fi
fi

# --- Validate -------------------------------------------------------------
is_valid_domain "$DOMAIN"     || { err "Invalid domain: $DOMAIN"; exit 1; }
is_valid_email "$EMAIL"       || { err "Invalid email: $EMAIL"; exit 1; }
is_valid_port "$BACKEND_PORT" || { err "Invalid backend port: $BACKEND_PORT"; exit 1; }

log "Domain:       $DOMAIN"
log "Email:        $EMAIL"
log "Backend port: 127.0.0.1:$BACKEND_PORT"
[[ "$STAGING" -eq 1 ]] && warn "Using Let's Encrypt STAGING (certs will NOT be trusted)."

# --- Ensure dependencies --------------------------------------------------
export DEBIAN_FRONTEND=noninteractive
if ! command -v nginx >/dev/null 2>&1; then
    err "Nginx is not installed. Install it first (e.g. ./install_nginx.sh)."
    exit 1
fi
if ! command -v certbot >/dev/null 2>&1; then
    log "Installing certbot..."
    apt-get update -y
    apt-get install -y certbot
fi

# --- Make sure port 80 is reachable; stop Nginx for standalone validation -
NGINX_WAS_ACTIVE=0
if systemctl is-active --quiet nginx; then
    NGINX_WAS_ACTIVE=1
fi

# Ensure Nginx is restarted even if certbot fails partway through.
restore_nginx() {
    if [[ "$NGINX_WAS_ACTIVE" -eq 1 ]]; then
        log "Re-enabling and starting Nginx..."
        systemctl start nginx || warn "Failed to start Nginx — check 'systemctl status nginx'."
    fi
}
trap restore_nginx EXIT

log "Stopping Nginx to free port 80 for standalone validation..."
systemctl stop nginx || true

# Open port 80/443 in ufw if it's active.
if command -v ufw >/dev/null 2>&1 && ufw status | grep -q "Status: active"; then
    log "Allowing 80/tcp and 443/tcp through ufw..."
    ufw allow 80/tcp  || true
    ufw allow 443/tcp || true
fi

# --- Obtain the certificate ----------------------------------------------
log "Requesting certificate from Let's Encrypt (standalone)..."
CERTBOT_ARGS=(
    certonly --standalone
    --non-interactive --agree-tos
    -m "$EMAIL"
    -d "$DOMAIN"
    --preferred-challenges http
)
[[ "$STAGING" -eq 1 ]] && CERTBOT_ARGS+=(--staging)

if ! certbot "${CERTBOT_ARGS[@]}"; then
    err "Certbot failed to obtain a certificate."
    err "Common causes: DNS for '$DOMAIN' not pointing here, or port 80 blocked."
    exit 1
fi

CERT_DIR="/etc/letsencrypt/live/${DOMAIN}"
if [[ ! -f "${CERT_DIR}/fullchain.pem" ]]; then
    err "Expected certificate not found at ${CERT_DIR}/fullchain.pem"
    exit 1
fi
log "Certificate obtained: ${CERT_DIR}/fullchain.pem"

# --- Update / write the Nginx server block with HTTPS --------------------
SITE_AVAIL="/etc/nginx/sites-available/${DOMAIN}.conf"
SITE_ENABLED="/etc/nginx/sites-enabled/${DOMAIN}.conf"

# Back up any existing config first.
if [[ -f "$SITE_AVAIL" ]]; then
    cp -a "$SITE_AVAIL" "${SITE_AVAIL}.bak.$(date +%s 2>/dev/null || echo backup)"
    log "Backed up existing config to ${SITE_AVAIL}.bak.*"
fi

log "Writing HTTPS server block to ${SITE_AVAIL}..."
cat > "$SITE_AVAIL" <<EOF
# Redirect all HTTP traffic to HTTPS.
server {
    listen 80;
    listen [::]:80;
    server_name ${DOMAIN};

    location /.well-known/acme-challenge/ {
        root /var/www/html;
    }

    location / {
        return 301 https://\$host\$request_uri;
    }
}

# HTTPS server.
server {
    listen 443 ssl;
    listen [::]:443 ssl;
    http2 on;
    server_name ${DOMAIN};

    ssl_certificate     ${CERT_DIR}/fullchain.pem;
    ssl_certificate_key ${CERT_DIR}/privkey.pem;
    ssl_protocols       TLSv1.2 TLSv1.3;
    ssl_ciphers         HIGH:!aNULL:!MD5;
    ssl_prefer_server_ciphers on;
    ssl_session_cache   shared:SSL:10m;
    ssl_session_timeout 1d;

    access_log /var/log/nginx/${DOMAIN}.access.log;
    error_log  /var/log/nginx/${DOMAIN}.error.log;

    location / {
        proxy_pass         http://127.0.0.1:${BACKEND_PORT};
        proxy_http_version 1.1;
        proxy_set_header   Host              \$host;
        proxy_set_header   X-Real-IP         \$remote_addr;
        proxy_set_header   X-Forwarded-For   \$proxy_add_x_forwarded_for;
        proxy_set_header   X-Forwarded-Proto \$scheme;
        proxy_set_header   Upgrade           \$http_upgrade;
        proxy_set_header   Connection        "upgrade";
    }
}
EOF

ln -sf "$SITE_AVAIL" "$SITE_ENABLED"
[[ -e /etc/nginx/sites-enabled/default ]] && rm -f /etc/nginx/sites-enabled/default

# --- Validate config, then let the EXIT trap bring Nginx back up ---------
log "Testing Nginx configuration..."
if ! nginx -t; then
    err "Nginx config test failed. Review ${SITE_AVAIL} (backup kept)."
    exit 1
fi

# Bring Nginx back regardless of its prior state now that config is valid.
NGINX_WAS_ACTIVE=1
trap - EXIT
log "Starting Nginx with the new HTTPS configuration..."
systemctl enable nginx >/dev/null 2>&1 || true
systemctl restart nginx

# --- Confirm auto-renewal is in place ------------------------------------
# Certbot installs a systemd timer (or cron) on install; verify it.
if systemctl list-timers 2>/dev/null | grep -q certbot; then
    log "Auto-renewal timer is active (certbot.timer)."
else
    warn "No certbot renewal timer found — renewals may not be automatic."
    warn "Test renewal manually with: certbot renew --dry-run"
fi

# Reload Nginx after renewals so new certs take effect.
RENEW_HOOK_DIR="/etc/letsencrypt/renewal-hooks/deploy"
mkdir -p "$RENEW_HOOK_DIR"
cat > "${RENEW_HOOK_DIR}/reload-nginx.sh" <<'EOF'
#!/usr/bin/env bash
systemctl reload nginx
EOF
chmod +x "${RENEW_HOOK_DIR}/reload-nginx.sh"
log "Installed renewal deploy-hook to reload Nginx after each renewal."

log "HTTPS is now configured for https://${DOMAIN}"
log "Done."
