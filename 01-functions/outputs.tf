output "function_app_name" {
  value = azurerm_function_app_flex_consumption.notes.name
}

output "function_app_url" {
  value = "https://${azurerm_function_app_flex_consumption.notes.default_hostname}/api"
}

output "resource_group_name" {
  value = azurerm_resource_group.notes.name
}

output "web_storage_name" {
  value = azurerm_storage_account.web.name
}

output "web_base_url" {
  value = azurerm_storage_account.web.primary_web_endpoint
}

output "entra_client_id" {
  value = azuread_application.notes.client_id
}

output "entra_authority" {
  value = "https://${var.entra_tenant_name}.ciamlogin.com/${var.entra_tenant_id}"
}
