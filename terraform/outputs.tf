# =============================================================================
# FORTRESS - Root Outputs
# =============================================================================

# ---------------------------------------------------------------------------
# Network IDs
# ---------------------------------------------------------------------------
output "dmz_network_id" {
  description = "Docker network ID for the DMZ zone"
  value       = module.network.dmz_network_id
}

output "app_network_id" {
  description = "Docker network ID for the App zone"
  value       = module.network.app_network_id
}

output "data_network_id" {
  description = "Docker network ID for the Data zone"
  value       = module.network.data_network_id
}

output "admin_network_id" {
  description = "Docker network ID for the Admin zone"
  value       = module.network.admin_network_id
}

# ---------------------------------------------------------------------------
# Container IPs
# ---------------------------------------------------------------------------
output "nginx_ip" {
  description = "IP address of the nginx container (DMZ zone)"
  value       = module.services.nginx_ip
}

output "flask_ip" {
  description = "IP address of the flask container (App zone)"
  value       = module.services.flask_ip
}

output "postgres_ip" {
  description = "IP address of the postgres container (Data zone)"
  value       = module.services.postgres_ip
}
