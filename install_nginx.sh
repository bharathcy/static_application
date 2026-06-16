#!/usr/bin/env bash
#
# install_nginx.sh — Install Nginx on Ubuntu and configure a reverse-proxy
# server block for a given domain.
#
# Usage:
#   sudo ./install_nginx.sh [-d DOMAIN] [-l LISTEN_PORT] [-b BACKEND_PORT] [-y]
#
# Options:
#   -d DOMAIN         Server name / domain (e.g. example.com)
#   -l LISTEN_PORT    Port Nginx listens on            (default: 80)
#   -b BACKEND_PORT   Local app port to proxy_pass to  (default: 3000)
#   -y                Non-interactive; use defaults / given args, no prompts
#   -h                Show this help
#
# Any value not supplied on the command line is prompted for interactively,
# unless -y is given.
#
set -euo pipefail

# --- Pretty logging -------------------------------------------------------
log()  { printf '\033[1;32m[+]\033[0m %s\n' "$*"; }
warn() { printf '\033[1;33m[!]\033[0m %s\n' "$*"; }
err()  { printf '\033[1;31m[-]\033[0m %s\n' "$*" >&2; }

usage() { sed -n '2,20p' "$0" | sed 's/^# \{0,1\}//'; exit "${1:-0}"; }

# --- Defaults & arg parsing ----------------------------------------------
DOMAIN=""
LISTEN_PORT=""
BACKEND_PORT=""
ASSUME_YES=0

while getopts ":d:l:b:yh" opt; do
    case "$opt" in
        d) DOMAIN="$OPTARG" ;;
        l) LISTEN_PORT="$OPTARG" ;;
        b) BACKEND_PORT="$OPTARG" ;;
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
is_valid_port() { [[ "$1" =~ ^[0-9]+$ ]] && (( $1 >= 1 && $1 <= 65535 )); }
is_valid_domain() { [[ "$1" =~ ^[A-Za-z0-9._-]+$ ]]; }

prompt_default() {            # prompt_default <varname> <message> <default>
    local __var="$1" __msg="$2" __def="$3" __input
    read -r -p "$__msg [$__def]: " __input
    printf -v "$__var" '%s' "${__input:-$__def}"
}

# --- Resolve configuration values ----------------------------------------
if [[ -z "$DOMAIN" ]]; then
    if [[ "$ASSUME_YES" -eq 1 ]]; then
        err "Domain (-d) is required in non-interactive mode."
        exit 1
    fi
    while :; do
        read -r -p "Enter domain / server name (e.g. example.com): " DOMAIN
        is_valid_domain "$DOMAIN" && [[ -n "$DOMAIN" ]] && break
        warn "Invalid domain. Use letters, digits, dots, hyphens."
    done
fi

if [[ -z "$LISTEN_PORT" ]]; then
    if [[ "$ASSUME_YES" -eq 1 ]]; then LISTEN_PORT=80
    else prompt_default LISTEN_PORT "Port for Nginx to listen on" 80; fi
fi

if [[ -z "$BACKEND_PORT" ]]; then
    if [[ "$ASSUME_YES" -eq 1 ]]; then BACKEND_PORT=3000
    else prompt_default BACKEND_PORT "Local backend/app port to proxy to" 3000; fi
fi

# --- Validate -------------------------------------------------------------
is_valid_domain "$DOMAIN"      || { err "Invalid domain: $DOMAIN"; exit 1; }
is_valid_port "$LISTEN_PORT"   || { err "Invalid listen port: $LISTEN_PORT"; exit 1; }
is_valid_port "$BACKEND_PORT"  || { err "Invalid backend port: $BACKEND_PORT"; exit 1; }

log "Domain:        $DOMAIN"
log "Listen port:   $LISTEN_PORT"
log "Backend port:  $BACKEND_PORT (proxied to 127.0.0.1:$BACKEND_PORT)"

# --- Install Nginx --------------------------------------------------------
if ! command -v nginx >/dev/null 2>&1; then
    log "Installing Nginx..."
    export DEBIAN_FRONTEND=noninteractive
    apt-get update -y
    apt-get install -y nginx
else
    log "Nginx already installed: $(nginx -v 2>&1)"
fi

# --- Write the server block ----------------------------------------------
SITE_AVAIL="/etc/nginx/sites-available/${DOMAIN}.conf"
SITE_ENABLED="/etc/nginx/sites-enabled/${DOMAIN}.conf"

log "Writing server block to ${SITE_AVAIL}..."
cat > "$SITE_AVAIL" <<EOF
server {
    listen ${LISTEN_PORT};
    listen [::]:${LISTEN_PORT};

    server_name ${DOMAIN};

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

# --- Enable the site ------------------------------------------------------
ln -sf "$SITE_AVAIL" "$SITE_ENABLED"

# Disable the default site if it's still enabled to avoid conflicts.
if [[ -e /etc/nginx/sites-enabled/default ]]; then
    log "Disabling default site to avoid conflicts..."
    rm -f /etc/nginx/sites-enabled/default
fi

# --- Open firewall (if ufw is active) ------------------------------------
if command -v ufw >/dev/null 2>&1 && ufw status | grep -q "Status: active"; then
    log "Allowing port ${LISTEN_PORT}/tcp through ufw..."
    ufw allow "${LISTEN_PORT}/tcp" || true
fi

# --- Test config & reload -------------------------------------------------
log "Testing Nginx configuration..."
if nginx -t; then
    log "Reloading Nginx..."
    systemctl enable nginx >/dev/null 2>&1 || true
    systemctl reload nginx || systemctl restart nginx
    log "Nginx configured for '${DOMAIN}' on port ${LISTEN_PORT} -> 127.0.0.1:${BACKEND_PORT}"
else
    err "Nginx config test failed. Server block left at ${SITE_AVAIL}."
    exit 1
fi

log "Done."
