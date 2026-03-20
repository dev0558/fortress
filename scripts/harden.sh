#!/usr/bin/env bash
# =============================================================================
# FORTRESS Hardening Script
# =============================================================================
# Idempotent system hardening script that applies firewall rules for zone
# isolation and configures intrusion prevention via fail2ban.
#
# Zone Architecture:
#   DMZ   (10.10.1.0/24) - Public-facing services (nginx)
#   App   (10.10.2.0/24) - Application tier (flask)
#   Data  (10.10.3.0/24) - Database tier (postgres)
#   Admin (10.10.4.0/24) - Management network
#
# Traffic Policy:
#   DMZ   -> App only
#   App   -> Data only
#   Data  -> (no outbound to other zones)
#   Admin -> All zones
#
# Usage:
#   ./harden.sh --all          Run all hardening steps
#   ./harden.sh --iptables     Apply iptables rules only
#   ./harden.sh --nftables     Apply nftables rules only
#   ./harden.sh --fail2ban     Configure fail2ban only
# =============================================================================

set -euo pipefail

# ---------------------------------------------------------------------------
# Constants
# ---------------------------------------------------------------------------
readonly DMZ_SUBNET="10.10.1.0/24"
readonly APP_SUBNET="10.10.2.0/24"
readonly DATA_SUBNET="10.10.3.0/24"
readonly ADMIN_SUBNET="10.10.4.0/24"

readonly IPTABLES_CHAIN="FORTRESS_ZONE_ISOLATION"
readonly NFTABLES_TABLE="fortress"
readonly FAIL2BAN_JAIL_NAME="nginx-fortress"
readonly FAIL2BAN_JAIL_FILE="/etc/fail2ban/jail.d/nginx-fortress.conf"
readonly FAIL2BAN_FILTER_FILE="/etc/fail2ban/filter.d/nginx-fortress.conf"

# ---------------------------------------------------------------------------
# Logging helpers
# ---------------------------------------------------------------------------
log_info()  { echo "[INFO]  $(date '+%Y-%m-%d %H:%M:%S') $*"; }
log_warn()  { echo "[WARN]  $(date '+%Y-%m-%d %H:%M:%S') $*" >&2; }
log_error() { echo "[ERROR] $(date '+%Y-%m-%d %H:%M:%S') $*" >&2; }

# ---------------------------------------------------------------------------
# Pre-flight checks
# ---------------------------------------------------------------------------
require_root() {
    if [[ $EUID -ne 0 ]]; then
        log_error "This script must be run as root."
        exit 1
    fi
}

command_exists() {
    command -v "$1" &>/dev/null
}

# ---------------------------------------------------------------------------
# iptables zone isolation
# ---------------------------------------------------------------------------
apply_iptables() {
    log_info "Applying iptables zone isolation rules..."

    if ! command_exists iptables; then
        log_error "iptables not found. Install it first."
        return 1
    fi

    # -- Idempotency: flush our custom chain if it already exists -----------
    if iptables -L "$IPTABLES_CHAIN" -n &>/dev/null; then
        log_info "Chain $IPTABLES_CHAIN already exists — flushing for idempotent re-apply."
        # Remove references from FORWARD chain before flushing
        while iptables -D FORWARD -j "$IPTABLES_CHAIN" 2>/dev/null; do :; done
        iptables -F "$IPTABLES_CHAIN"
        iptables -X "$IPTABLES_CHAIN"
    fi

    # -- Create the custom chain --------------------------------------------
    iptables -N "$IPTABLES_CHAIN"

    # -- Allow established / related connections (stateful tracking) ---------
    iptables -A "$IPTABLES_CHAIN" -m conntrack --ctstate ESTABLISHED,RELATED -j ACCEPT

    # -- Admin zone can reach ALL other zones -------------------------------
    iptables -A "$IPTABLES_CHAIN" -s "$ADMIN_SUBNET" -d "$DMZ_SUBNET"  -j ACCEPT
    iptables -A "$IPTABLES_CHAIN" -s "$ADMIN_SUBNET" -d "$APP_SUBNET"  -j ACCEPT
    iptables -A "$IPTABLES_CHAIN" -s "$ADMIN_SUBNET" -d "$DATA_SUBNET" -j ACCEPT

    # -- DMZ can reach App zone only ----------------------------------------
    iptables -A "$IPTABLES_CHAIN" -s "$DMZ_SUBNET" -d "$APP_SUBNET" -j ACCEPT

    # -- DMZ cannot reach Data or Admin -------------------------------------
    iptables -A "$IPTABLES_CHAIN" -s "$DMZ_SUBNET" -d "$DATA_SUBNET"  -j DROP
    iptables -A "$IPTABLES_CHAIN" -s "$DMZ_SUBNET" -d "$ADMIN_SUBNET" -j DROP

    # -- App can reach Data zone only ---------------------------------------
    iptables -A "$IPTABLES_CHAIN" -s "$APP_SUBNET" -d "$DATA_SUBNET" -j ACCEPT

    # -- App cannot reach Admin or DMZ --------------------------------------
    iptables -A "$IPTABLES_CHAIN" -s "$APP_SUBNET" -d "$ADMIN_SUBNET" -j DROP
    iptables -A "$IPTABLES_CHAIN" -s "$APP_SUBNET" -d "$DMZ_SUBNET"   -j DROP

    # -- Data zone cannot initiate connections to DMZ or Admin --------------
    iptables -A "$IPTABLES_CHAIN" -s "$DATA_SUBNET" -d "$DMZ_SUBNET"   -j DROP
    iptables -A "$IPTABLES_CHAIN" -s "$DATA_SUBNET" -d "$APP_SUBNET"   -j DROP
    iptables -A "$IPTABLES_CHAIN" -s "$DATA_SUBNET" -d "$ADMIN_SUBNET" -j DROP

    # -- Hook custom chain into FORWARD -------------------------------------
    iptables -A FORWARD -j "$IPTABLES_CHAIN"

    log_info "iptables zone isolation rules applied successfully."
}

# ---------------------------------------------------------------------------
# nftables zone isolation (backup / alternative to iptables)
# ---------------------------------------------------------------------------
apply_nftables() {
    log_info "Applying nftables zone isolation rules (backup firewall)..."

    if ! command_exists nft; then
        log_error "nft not found. Install nftables first."
        return 1
    fi

    # -- Idempotency: delete existing table if present ----------------------
    if nft list table inet "$NFTABLES_TABLE" &>/dev/null; then
        log_info "nftables table '$NFTABLES_TABLE' already exists — deleting for idempotent re-apply."
        nft delete table inet "$NFTABLES_TABLE"
    fi

    # -- Build the ruleset atomically ---------------------------------------
    nft -f - <<NFTEOF
table inet $NFTABLES_TABLE {
    chain forward {
        type filter hook forward priority 0; policy drop;

        # Allow established / related connections
        ct state established,related accept

        # Admin -> all zones
        ip saddr $ADMIN_SUBNET ip daddr $DMZ_SUBNET  accept
        ip saddr $ADMIN_SUBNET ip daddr $APP_SUBNET  accept
        ip saddr $ADMIN_SUBNET ip daddr $DATA_SUBNET accept

        # DMZ -> App only
        ip saddr $DMZ_SUBNET ip daddr $APP_SUBNET accept

        # App -> Data only
        ip saddr $APP_SUBNET ip daddr $DATA_SUBNET accept

        # Everything else is dropped by default policy
    }
}
NFTEOF

    log_info "nftables zone isolation rules applied successfully."
}

# ---------------------------------------------------------------------------
# fail2ban configuration with custom nginx jail
# ---------------------------------------------------------------------------
configure_fail2ban() {
    log_info "Configuring fail2ban with custom nginx jail..."

    if ! command_exists fail2ban-client; then
        log_error "fail2ban-client not found. Install fail2ban first."
        return 1
    fi

    # -- Create custom filter for nginx suspicious activity -----------------
    # Idempotent: overwrite if file already exists
    mkdir -p "$(dirname "$FAIL2BAN_FILTER_FILE")"
    cat > "$FAIL2BAN_FILTER_FILE" <<'FILTEREOF'
# FORTRESS custom fail2ban filter for nginx
# Detects common attack patterns: path traversal, scanner probes, auth failures
[Definition]

# Matches HTTP 4xx responses that indicate malicious probing
failregex = ^<HOST> .* "(GET|POST|HEAD|PUT|DELETE) .*(\.\.\/|\.env|wp-login|phpMyAdmin|admin|shell|eval|passwd).*" (400|401|403|404|444) .*$
            ^<HOST> .* ".*" 401 .*$

# Ignore legitimate 404s for common static assets
ignoreregex = ^<HOST> .* "(GET|POST) .*\.(css|js|ico|png|jpg|jpeg|gif|svg|woff2?|ttf|eot)" 404 .*$
FILTEREOF

    # -- Create the jail configuration --------------------------------------
    mkdir -p "$(dirname "$FAIL2BAN_JAIL_FILE")"
    cat > "$FAIL2BAN_JAIL_FILE" <<JAILEOF
# FORTRESS custom fail2ban jail for nginx
# Bans IPs that trigger suspicious requests against the DMZ nginx proxy.

[$FAIL2BAN_JAIL_NAME]
enabled  = true
port     = http,https
filter   = nginx-fortress
logpath  = /var/log/nginx/access.log
           /var/log/nginx/error.log

# Ban after 5 failures within 10 minutes
maxretry = 5
findtime = 600

# Ban duration: 1 hour (3600 seconds)
bantime  = 3600

# Use iptables-multiport for banning action
action   = iptables-multiport[name=nginx-fortress, port="http,https", protocol=tcp]
JAILEOF

    # -- Reload fail2ban to pick up changes ---------------------------------
    if systemctl is-active --quiet fail2ban; then
        fail2ban-client reload
        log_info "fail2ban reloaded with updated configuration."
    else
        log_warn "fail2ban service is not running. Start it with: systemctl start fail2ban"
    fi

    log_info "fail2ban custom nginx jail configured at $FAIL2BAN_JAIL_FILE"
}

# ---------------------------------------------------------------------------
# Usage / help
# ---------------------------------------------------------------------------
usage() {
    cat <<EOF
Usage: $(basename "$0") [OPTIONS]

Options:
  --all         Run all hardening steps (iptables + nftables + fail2ban)
  --iptables    Apply iptables zone isolation rules
  --nftables    Apply nftables zone isolation rules (backup)
  --fail2ban    Configure fail2ban with custom nginx jail
  -h, --help    Show this help message

Examples:
  sudo ./harden.sh --all
  sudo ./harden.sh --iptables --fail2ban
EOF
    exit 0
}

# ---------------------------------------------------------------------------
# Main
# ---------------------------------------------------------------------------
main() {
    if [[ $# -eq 0 ]]; then
        usage
    fi

    local do_iptables=false
    local do_nftables=false
    local do_fail2ban=false

    while [[ $# -gt 0 ]]; do
        case "$1" in
            --all)
                do_iptables=true
                do_nftables=true
                do_fail2ban=true
                ;;
            --iptables)  do_iptables=true ;;
            --nftables)  do_nftables=true ;;
            --fail2ban)  do_fail2ban=true ;;
            -h|--help)   usage ;;
            *)
                log_error "Unknown option: $1"
                usage
                ;;
        esac
        shift
    done

    require_root

    log_info "=== FORTRESS Hardening Script Started ==="

    if $do_iptables; then apply_iptables; fi
    if $do_nftables; then apply_nftables; fi
    if $do_fail2ban; then configure_fail2ban; fi

    log_info "=== FORTRESS Hardening Script Completed ==="
}

main "$@"
