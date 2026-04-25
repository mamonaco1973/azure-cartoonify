output "resource_group_name" {
  value = azurerm_resource_group.cartoonify.name
}

output "web_storage_name" {
  value = azurerm_storage_account.web.name
}

output "web_base_url" {
  value = azurerm_storage_account.web.primary_web_endpoint
}

output "media_storage_name" {
  value = azurerm_storage_account.media.name
}

output "media_storage_key" {
  value     = azurerm_storage_account.media.primary_access_key
  sensitive = true
}

output "media_blob_endpoint" {
  value = azurerm_storage_account.media.primary_blob_endpoint
}

output "cosmos_endpoint" {
  value = azurerm_cosmosdb_account.cartoonify.endpoint
}

output "cosmos_account_name" {
  value = azurerm_cosmosdb_account.cartoonify.name
}

output "cosmos_role_definition_id" {
  value = azurerm_cosmosdb_sql_role_definition.func_role.id
}

output "servicebus_namespace_fqdn" {
  value = "${azurerm_servicebus_namespace.cartoonify.name}.servicebus.windows.net"
}

output "servicebus_queue_name" {
  value = azurerm_servicebus_queue.jobs.name
}

output "servicebus_queue_id" {
  value = azurerm_servicebus_queue.jobs.id
}

output "openai_endpoint" {
  value = azurerm_cognitive_account.openai.endpoint
}

output "openai_account_id" {
  value = azurerm_cognitive_account.openai.id
}

output "openai_deployment_name" {
  value = azurerm_cognitive_deployment.gpt_image_1.name
}

output "entra_client_id" {
  value = azuread_application.cartoonify.client_id
}

output "entra_authority" {
  value = "https://${var.entra_tenant_name}.ciamlogin.com/${var.entra_tenant_id}"
}
