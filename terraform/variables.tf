# =============================================================================
# FORTRESS - Input Variables
# =============================================================================

# ---------------------------------------------------------------------------
# General
# ---------------------------------------------------------------------------
variable "project_name" {
  description = "Prefix for all resource names"
  type        = string
  default     = "fortress"
}

variable "docker_host" {
  description = "Docker daemon socket URI"
  type        = string
  default     = "unix:///var/run/docker.sock"
}

# ---------------------------------------------------------------------------
# Network Subnets
# ---------------------------------------------------------------------------
variable "dmz_subnet" {
  description = "CIDR block for the DMZ network zone"
  type        = string
  default     = "10.10.1.0/24"
}

variable "app_subnet" {
  description = "CIDR block for the App network zone"
  type        = string
  default     = "10.10.2.0/24"
}

variable "data_subnet" {
  description = "CIDR block for the Data network zone"
  type        = string
  default     = "10.10.3.0/24"
}

variable "admin_subnet" {
  description = "CIDR block for the Admin network zone"
  type        = string
  default     = "10.10.4.0/24"
}

# ---------------------------------------------------------------------------
# Container Images
# ---------------------------------------------------------------------------
variable "nginx_image" {
  description = "Docker image for the DMZ reverse proxy (nginx)"
  type        = string
  default     = "nginx:alpine"
}

variable "flask_image" {
  description = "Docker image for the App tier (flask)"
  type        = string
  default     = "python:3.11-slim"
}

variable "postgres_image" {
  description = "Docker image for the Data tier (postgres)"
  type        = string
  default     = "postgres:16-alpine"
}

# ---------------------------------------------------------------------------
# Secrets
# ---------------------------------------------------------------------------
variable "postgres_password" {
  description = "Password for the PostgreSQL database"
  type        = string
  sensitive   = true
  default     = "changeme-in-production"
}
