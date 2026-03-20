# =============================================================================
# FORTRESS - Services Module Outputs
# =============================================================================

# ---------------------------------------------------------------------------
# Container IDs
# ---------------------------------------------------------------------------

output "nginx_container_id" {
  description = "ID of the nginx container"
  value       = docker_container.nginx.id
}

output "flask_container_id" {
  description = "ID of the flask container"
  value       = docker_container.flask.id
}

output "postgres_container_id" {
  description = "ID of the postgres container"
  value       = docker_container.postgres.id
}

# ---------------------------------------------------------------------------
# Container IPs
# ---------------------------------------------------------------------------

output "nginx_ip" {
  description = "IP address of the nginx container in the DMZ zone"
  value       = "10.10.1.10"
}

output "flask_ip" {
  description = "IP address of the flask container in the App zone"
  value       = "10.10.2.20"
}

output "postgres_ip" {
  description = "IP address of the postgres container in the Data zone"
  value       = "10.10.3.30"
}

# ---------------------------------------------------------------------------
# Container Names
# ---------------------------------------------------------------------------

output "nginx_container_name" {
  description = "Name of the nginx container"
  value       = docker_container.nginx.name
}

output "flask_container_name" {
  description = "Name of the flask container"
  value       = docker_container.flask.name
}

output "postgres_container_name" {
  description = "Name of the postgres container"
  value       = docker_container.postgres.name
}
