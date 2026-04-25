variable "location" {
  description = "Azure region — must match 01-backend"
  type        = string
  default     = "East US"
}

variable "resource_group_name" {
  description = "Resource group created by 01-backend"
  type        = string
  default     = "cartoonify-rg"
}

variable "servicebus_namespace_fqdn" {
  type = string
}

variable "servicebus_queue_name" {
  type = string
}

variable "servicebus_queue_id" {
  type = string
}

variable "cosmos_endpoint" {
  type = string
}

variable "cosmos_account_name" {
  type = string
}

variable "cosmos_role_definition_id" {
  type = string
}

variable "media_storage_name" {
  type = string
}

variable "media_storage_key" {
  type      = string
  sensitive = true
}

variable "media_blob_endpoint" {
  type = string
}

variable "openai_endpoint" {
  type = string
}

variable "openai_account_id" {
  type = string
}

variable "openai_deployment_name" {
  type = string
}

variable "entra_tenant_name" {
  type = string
}

variable "entra_tenant_id" {
  type = string
}

variable "entra_client_id" {
  type = string
}

variable "web_origin" {
  description = "Web storage primary_web_endpoint (for CORS)"
  type        = string
}
