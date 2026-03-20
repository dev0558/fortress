# =============================================================================
# FORTRESS - Network Module Outputs
# =============================================================================

output "dmz_network_id" {
  description = "ID of the DMZ Docker network"
  value       = docker_network.dmz.id
}

output "dmz_network_name" {
  description = "Name of the DMZ Docker network"
  value       = docker_network.dmz.name
}

output "app_network_id" {
  description = "ID of the App Docker network"
  value       = docker_network.app.id
}

output "app_network_name" {
  description = "Name of the App Docker network"
  value       = docker_network.app.name
}

output "data_network_id" {
  description = "ID of the Data Docker network"
  value       = docker_network.data.id
}

output "data_network_name" {
  description = "Name of the Data Docker network"
  value       = docker_network.data.name
}

output "admin_network_id" {
  description = "ID of the Admin Docker network"
  value       = docker_network.admin.id
}

output "admin_network_name" {
  description = "Name of the Admin Docker network"
  value       = docker_network.admin.name
}
