# =============================================================================
# FORTRESS - Firewall Module Variables
# =============================================================================

variable "dmz_subnet" {
  description = "CIDR block for the DMZ network zone"
  type        = string
}

variable "app_subnet" {
  description = "CIDR block for the App network zone"
  type        = string
}

variable "data_subnet" {
  description = "CIDR block for the Data network zone"
  type        = string
}

variable "admin_subnet" {
  description = "CIDR block for the Admin network zone"
  type        = string
}
