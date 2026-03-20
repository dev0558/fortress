# =============================================================================
# FORTRESS - Firewall Module Outputs
# =============================================================================

output "iptables_chain_name" {
  description = "Name of the custom iptables chain used for zone isolation"
  value       = "FORTRESS_ZONE_ISOLATION"
}

output "firewall_rules_applied" {
  description = "Whether the firewall rules have been applied (resource ID)"
  value       = null_resource.iptables_zone_isolation.id
}

output "zone_policy_summary" {
  description = "Human-readable summary of the zone isolation policy"
  value = {
    "admin_to_all"  = "ALLOW"
    "dmz_to_app"    = "ALLOW"
    "dmz_to_data"   = "DENY"
    "dmz_to_admin"  = "DENY"
    "app_to_data"   = "ALLOW"
    "app_to_admin"  = "DENY"
    "app_to_dmz"    = "DENY"
    "data_to_dmz"   = "DENY"
    "data_to_app"   = "DENY"
    "data_to_admin" = "DENY"
  }
}
