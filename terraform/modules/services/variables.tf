# =============================================================================
# FORTRESS - Services Module Variables
# =============================================================================

# ---------------------------------------------------------------------------
# General
# ---------------------------------------------------------------------------

variable "project_name" {
  description = "Prefix for all resource names"
  type        = string
}

# ---------------------------------------------------------------------------
# Network IDs (passed from the network module)
# ---------------------------------------------------------------------------

variable "dmz_network_id" {
  description = "ID of the DMZ Docker network"
  type        = string
}

variable "app_network_id" {
  description = "ID of the App Docker network"
  type        = string
}

variable "data_network_id" {
  description = "ID of the Data Docker network"
  type        = string
}

variable "admin_network_id" {
  description = "ID of the Admin Docker network"
  type        = string
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
}
