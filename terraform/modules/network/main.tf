# =============================================================================
# FORTRESS - Network Module
# =============================================================================
# Creates four isolated Docker networks representing the security zones:
#   DMZ   - Public-facing services
#   App   - Application tier
#   Data  - Database tier
#   Admin - Management / operations
#
# Each network uses an internal driver with a dedicated subnet to ensure
# strict isolation between zones.
# =============================================================================

# ---------------------------------------------------------------------------
# DMZ Network (10.10.1.0/24)
# Hosts the nginx reverse proxy that accepts external traffic.
# ---------------------------------------------------------------------------
resource "docker_network" "dmz" {
  name     = "${var.project_name}-dmz"
  driver   = "bridge"
  internal = false # DMZ is externally accessible

  ipam_config {
    subnet  = var.dmz_subnet
    gateway = cidrhost(var.dmz_subnet, 1)
  }

  labels {
    label = "zone"
    value = "dmz"
  }

  labels {
    label = "project"
    value = var.project_name
  }
}

# ---------------------------------------------------------------------------
# App Network (10.10.2.0/24)
# Hosts the Flask application server. Only reachable from DMZ.
# ---------------------------------------------------------------------------
resource "docker_network" "app" {
  name     = "${var.project_name}-app"
  driver   = "bridge"
  internal = true # Not directly accessible from outside

  ipam_config {
    subnet  = var.app_subnet
    gateway = cidrhost(var.app_subnet, 1)
  }

  labels {
    label = "zone"
    value = "app"
  }

  labels {
    label = "project"
    value = var.project_name
  }
}

# ---------------------------------------------------------------------------
# Data Network (10.10.3.0/24)
# Hosts the PostgreSQL database. Only reachable from App zone.
# ---------------------------------------------------------------------------
resource "docker_network" "data" {
  name     = "${var.project_name}-data"
  driver   = "bridge"
  internal = true # Fully isolated from external access

  ipam_config {
    subnet  = var.data_subnet
    gateway = cidrhost(var.data_subnet, 1)
  }

  labels {
    label = "zone"
    value = "data"
  }

  labels {
    label = "project"
    value = var.project_name
  }
}

# ---------------------------------------------------------------------------
# Admin Network (10.10.4.0/24)
# Management network with access to all zones for operations.
# ---------------------------------------------------------------------------
resource "docker_network" "admin" {
  name     = "${var.project_name}-admin"
  driver   = "bridge"
  internal = true # Only accessible to admin containers

  ipam_config {
    subnet  = var.admin_subnet
    gateway = cidrhost(var.admin_subnet, 1)
  }

  labels {
    label = "zone"
    value = "admin"
  }

  labels {
    label = "project"
    value = var.project_name
  }
}
