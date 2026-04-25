output "function_app_name" {
  value = azurerm_function_app_flex_consumption.cartoonify.name
}

output "function_app_url" {
  value = "https://${azurerm_function_app_flex_consumption.cartoonify.default_hostname}/api"
}
