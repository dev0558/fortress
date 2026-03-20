# =============================================================================
# FORTRESS - Services Module
# =============================================================================
# Deploys Docker containers into their respective network zones:
#   nginx    -> DMZ zone  (reverse proxy, public entry point)
#   flask    -> App zone  (application server, also connected to Data for DB)
#   postgres -> Data zone (database, fully isolated)
#
# Each container follows least-privilege principles:
#   - Capabilities dropped
#   - Read-only root filesystem where possible
#   - No new privileges
# =============================================================================

terraform {
  required_providers {
    docker = {
      source  = "kreuzwerker/docker"
      version = "~> 3.0"
    }
  }
}

# ---------------------------------------------------------------------------
# Pull container images
# ---------------------------------------------------------------------------

resource "docker_image" "nginx" {
  name         = var.nginx_image
  keep_locally = true
}

resource "docker_image" "flask" {
  name         = var.flask_image
  keep_locally = true
}

resource "docker_image" "postgres" {
  name         = var.postgres_image
  keep_locally = true
}

# ---------------------------------------------------------------------------
# Nginx Container (DMZ Zone)
# ---------------------------------------------------------------------------
# The nginx reverse proxy sits in the DMZ and forwards traffic to the App
# zone. It is also attached to the App network so it can reach Flask.
# ---------------------------------------------------------------------------

resource "docker_container" "nginx" {
  name  = "${var.project_name}-nginx"
  image = docker_image.nginx.image_id

  # Expose HTTP on the host
  ports {
    internal = 80
    external = 8080
  }

  # Attach to DMZ (primary) and App (for upstream proxying)
  networks_advanced {
    name         = var.dmz_network_id
    ipv4_address = "10.10.1.10"
  }

  networks_advanced {
    name         = var.app_network_id
    ipv4_address = "10.10.2.10"
  }

  # Security hardening
  read_only = true
  must_run  = true

  # Tmpfs mounts for writable directories nginx requires
  tmpfs = {
    "/tmp"             = "rw,noexec,nosuid"
    "/var/cache/nginx" = "rw,noexec,nosuid"
    "/var/run"         = "rw,noexec,nosuid"
  }

  restart = "unless-stopped"

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
# Flask Container (App Zone)
# ---------------------------------------------------------------------------
# The Flask application server sits in the App zone and connects to the Data
# zone to reach PostgreSQL. It is NOT connected to DMZ or Admin.
# ---------------------------------------------------------------------------

resource "docker_container" "flask" {
  name  = "${var.project_name}-flask"
  image = docker_image.flask.image_id

  # Attach to App (primary) and Data (for database access)
  networks_advanced {
    name         = var.app_network_id
    ipv4_address = "10.10.2.20"
  }

  networks_advanced {
    name         = var.data_network_id
    ipv4_address = "10.10.3.20"
  }

  # Application environment
  env = [
    "DATABASE_HOST=10.10.3.30",
    "DATABASE_PORT=5432",
    "FLASK_ENV=production",
  ]

  # Security hardening
  read_only = true
  must_run  = true

  tmpfs = {
    "/tmp" = "rw,noexec,nosuid"
  }

  restart = "unless-stopped"

  # Flask needs to start after postgres is available
  depends_on = [docker_container.postgres]

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
# PostgreSQL Container (Data Zone)
# ---------------------------------------------------------------------------
# The PostgreSQL database sits exclusively in the Data zone. It is only
# reachable from the App zone (via Flask). No external or DMZ access.
# ---------------------------------------------------------------------------

resource "docker_container" "postgres" {
  name  = "${var.project_name}-postgres"
  image = docker_image.postgres.image_id

  # Attach to Data zone only
  networks_advanced {
    name         = var.data_network_id
    ipv4_address = "10.10.3.30"
  }

  # Database environment
  env = [
    "POSTGRES_USER=fortress",
    "POSTGRES_DB=fortress",
    "POSTGRES_PASSWORD=${var.postgres_password}",
  ]

  # Persistent volume for database data
  volumes {
    volume_name    = docker_volume.pgdata.name
    container_path = "/var/lib/postgresql/data"
  }

  must_run = true
  restart  = "unless-stopped"

  # Health check to verify postgres is accepting connections
  healthcheck {
    test         = ["CMD-SHELL", "pg_isready -U fortress -d fortress"]
    interval     = "10s"
    timeout      = "5s"
    retries      = 5
    start_period = "15s"
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
# Persistent volume for PostgreSQL data
# ---------------------------------------------------------------------------

resource "docker_volume" "pgdata" {
  name = "${var.project_name}-pgdata"
}
