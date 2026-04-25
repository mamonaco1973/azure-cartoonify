variable "location" {
  description = "Azure region for all resources"
  type        = string
  default     = "Central US"
}

variable "entra_tenant_id" {
  description = "Microsoft Entra External ID tenant ID (GUID)"
  type        = string
}

variable "entra_tenant_name" {
  description = "Entra External tenant name prefix (e.g. 'mynotesapp' from mynotesapp.onmicrosoft.com)"
  type        = string
}

variable "entra_sp_client_id" {
  description = "Client ID of a service principal registered IN the Entra External tenant"
  type        = string
}

variable "entra_sp_client_secret" {
  description = "Client secret of the Entra External tenant service principal"
  type        = string
  sensitive   = true
}
