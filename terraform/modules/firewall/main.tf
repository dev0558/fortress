# =============================================================================
# FORTRESS - Firewall Module
# =============================================================================
# Applies iptables rules to enforce zone isolation at the Docker host level.
# Uses null_resource provisioners to execute iptables commands.
#
# Traffic Policy:
#   Admin (10.10.4.0/24) -> DMZ, App, Data  : ALLOW
#   DMZ   (10.10.1.0/24) -> App             : ALLOW
#   DMZ   (10.10.1.0/24) -> Data, Admin     : DENY
#   App   (10.10.2.0/24) -> Data            : ALLOW
#   App   (10.10.2.0/24) -> Admin, DMZ      : DENY
#   Data  (10.10.3.0/24) -> DMZ, App, Admin : DENY
#
# Idempotency: The provisioner flushes and recreates the custom chain on
# every apply, making it safe to run repeatedly.
# =============================================================================

terraform {
  required_providers {
    null = {
      source  = "hashicorp/null"
      version = "~> 3.0"
    }
  }
}

# ---------------------------------------------------------------------------
# Local values for readability
# ---------------------------------------------------------------------------

locals {
  chain_name = "FORTRESS_ZONE_ISOLATION"
}

# ---------------------------------------------------------------------------
# Zone Isolation Rules via iptables
# ---------------------------------------------------------------------------
# This null_resource applies the full set of iptables rules for zone
# isolation. The triggers block forces re-creation whenever subnets change.
# ---------------------------------------------------------------------------

resource "null_resource" "iptables_zone_isolation" {
  # Re-apply rules if any subnet configuration changes
  triggers = {
    dmz_subnet   = var.dmz_subnet
    app_subnet   = var.app_subnet
    data_subnet  = var.data_subnet
    admin_subnet = var.admin_subnet
    chain_name   = local.chain_name
  }

  # -------------------------------------------------------------------------
  # Create: Apply the iptables zone isolation rules
  # -------------------------------------------------------------------------
  provisioner "local-exec" {
    interpreter = ["/bin/bash", "-c"]
    command     = <<-SCRIPT
      set -euo pipefail

      CHAIN="${local.chain_name}"
      DMZ="${var.dmz_subnet}"
      APP="${var.app_subnet}"
      DATA="${var.data_subnet}"
      ADMIN="${var.admin_subnet}"

      echo "[FORTRESS] Applying iptables zone isolation rules..."

      # -- Idempotency: remove existing chain if present --------------------
      if iptables -L "$CHAIN" -n &>/dev/null; then
        echo "[FORTRESS] Chain $CHAIN exists - removing for clean re-apply..."
        # Remove all references from FORWARD chain
        while iptables -D FORWARD -j "$CHAIN" 2>/dev/null; do :; done
        iptables -F "$CHAIN"
        iptables -X "$CHAIN"
      fi

      # -- Create custom chain ---------------------------------------------
      iptables -N "$CHAIN"

      # -- Stateful: allow established/related connections ------------------
      iptables -A "$CHAIN" -m conntrack --ctstate ESTABLISHED,RELATED -j ACCEPT

      # -- Admin zone can reach ALL other zones -----------------------------
      iptables -A "$CHAIN" -s "$ADMIN" -d "$DMZ"  -j ACCEPT -m comment --comment "Admin -> DMZ: ALLOW"
      iptables -A "$CHAIN" -s "$ADMIN" -d "$APP"  -j ACCEPT -m comment --comment "Admin -> App: ALLOW"
      iptables -A "$CHAIN" -s "$ADMIN" -d "$DATA" -j ACCEPT -m comment --comment "Admin -> Data: ALLOW"

      # -- DMZ can reach App zone only --------------------------------------
      iptables -A "$CHAIN" -s "$DMZ" -d "$APP"   -j ACCEPT -m comment --comment "DMZ -> App: ALLOW"
      iptables -A "$CHAIN" -s "$DMZ" -d "$DATA"  -j DROP   -m comment --comment "DMZ -> Data: DENY"
      iptables -A "$CHAIN" -s "$DMZ" -d "$ADMIN" -j DROP   -m comment --comment "DMZ -> Admin: DENY"

      # -- App can reach Data zone only -------------------------------------
      iptables -A "$CHAIN" -s "$APP" -d "$DATA"  -j ACCEPT -m comment --comment "App -> Data: ALLOW"
      iptables -A "$CHAIN" -s "$APP" -d "$ADMIN" -j DROP   -m comment --comment "App -> Admin: DENY"
      iptables -A "$CHAIN" -s "$APP" -d "$DMZ"   -j DROP   -m comment --comment "App -> DMZ: DENY"

      # -- Data zone cannot initiate connections to any other zone ----------
      iptables -A "$CHAIN" -s "$DATA" -d "$DMZ"   -j DROP -m comment --comment "Data -> DMZ: DENY"
      iptables -A "$CHAIN" -s "$DATA" -d "$APP"   -j DROP -m comment --comment "Data -> App: DENY"
      iptables -A "$CHAIN" -s "$DATA" -d "$ADMIN" -j DROP -m comment --comment "Data -> Admin: DENY"

      # -- Hook into the FORWARD chain --------------------------------------
      iptables -A FORWARD -j "$CHAIN"

      echo "[FORTRESS] iptables zone isolation rules applied successfully."
    SCRIPT
  }

  # -------------------------------------------------------------------------
  # Destroy: Clean up iptables rules when resources are torn down
  # -------------------------------------------------------------------------
  provisioner "local-exec" {
    when        = destroy
    interpreter = ["/bin/bash", "-c"]
    command     = <<-SCRIPT
      set -euo pipefail

      CHAIN="${self.triggers.chain_name}"

      echo "[FORTRESS] Removing iptables zone isolation rules..."

      if iptables -L "$CHAIN" -n &>/dev/null; then
        while iptables -D FORWARD -j "$CHAIN" 2>/dev/null; do :; done
        iptables -F "$CHAIN"
        iptables -X "$CHAIN"
        echo "[FORTRESS] Chain $CHAIN removed."
      else
        echo "[FORTRESS] Chain $CHAIN does not exist - nothing to remove."
      fi
    SCRIPT
  }
}

# ---------------------------------------------------------------------------
# Log the applied rules for audit trail
# ---------------------------------------------------------------------------

resource "null_resource" "iptables_audit_log" {
  depends_on = [null_resource.iptables_zone_isolation]

  triggers = {
    rules_id = null_resource.iptables_zone_isolation.id
  }

  provisioner "local-exec" {
    interpreter = ["/bin/bash", "-c"]
    command     = <<-SCRIPT
      echo "[FORTRESS] Current iptables FORTRESS_ZONE_ISOLATION rules:"
      iptables -L ${local.chain_name} -n -v --line-numbers 2>/dev/null || \
        echo "[FORTRESS] Warning: Could not list rules (chain may not exist yet)."
    SCRIPT
  }
}
