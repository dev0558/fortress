# =============================================================================
# FORTRESS - Network Module Variables
# =============================================================================

variable "project_name" {
  description = "Prefix for all resource names"
  type        = string
}

variable "dmz_subnet" {
  description = "CIDR block for the DMZ network"
  type        = string
}

variable "app_subnet" {
  description = "CIDR block for the App network"
  type        = string
}

variable "data_subnet" {
  description = "CIDR block for the Data network"
  type        = string
}

variable "admin_subnet" {
  description = "CIDR block for the Admin network"
  type        = string
}
