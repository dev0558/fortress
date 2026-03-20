# =============================================================================
# FORTRESS - Root Terraform Configuration
# =============================================================================
# Orchestrates the creation of isolated Docker networks, service containers,
# and firewall rules for a multi-zone security architecture.
#
# Zones: DMZ, App, Data, Admin
# =============================================================================

terraform {
  required_version = ">= 1.0.0"

  required_providers {
    docker = {
      source  = "kreuzwerker/docker"
      version = "~> 3.0"
    }
  }
}

# ---------------------------------------------------------------------------
# Docker Provider
# ---------------------------------------------------------------------------
provider "docker" {
  host = var.docker_host
}

# ---------------------------------------------------------------------------
# Module: Network
# Creates the four isolated Docker networks (DMZ, App, Data, Admin).
# ---------------------------------------------------------------------------
module "network" {
  source = "./modules/network"

  project_name = var.project_name
  dmz_subnet   = var.dmz_subnet
  app_subnet   = var.app_subnet
  data_subnet  = var.data_subnet
  admin_subnet = var.admin_subnet
}

# ---------------------------------------------------------------------------
# Module: Services
# Deploys the application containers into the correct network zones.
# ---------------------------------------------------------------------------
module "services" {
  source = "./modules/services"

  project_name = var.project_name

  dmz_network_id   = module.network.dmz_network_id
  app_network_id   = module.network.app_network_id
  data_network_id  = module.network.data_network_id
  admin_network_id = module.network.admin_network_id

  nginx_image    = var.nginx_image
  flask_image    = var.flask_image
  postgres_image = var.postgres_image

  postgres_password = var.postgres_password
}

# ---------------------------------------------------------------------------
# Module: Firewall
# Applies iptables rules to enforce zone isolation policies.
# ---------------------------------------------------------------------------
module "firewall" {
  source = "./modules/firewall"

  dmz_subnet   = var.dmz_subnet
  app_subnet   = var.app_subnet
  data_subnet  = var.data_subnet
  admin_subnet = var.admin_subnet

  # Ensure networks and services are created before applying firewall rules
  depends_on = [
    module.network,
    module.services,
  ]
}
