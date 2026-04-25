data "azurerm_storage_account" "web" {
  name                = var.web_storage_name
  resource_group_name = "notes-entra-rg"
}

resource "azurerm_storage_blob" "index" {
  name                   = "index.html"
  storage_account_name   = data.azurerm_storage_account.web.name
  storage_container_name = "$web"
  type                   = "Block"
  source                 = "index.html"
  content_type           = "text/html"
  cache_control          = "no-store"
  content_md5            = filemd5("index.html")
}

resource "azurerm_storage_blob" "callback" {
  name                   = "callback.html"
  storage_account_name   = data.azurerm_storage_account.web.name
  storage_container_name = "$web"
  type                   = "Block"
  source                 = "callback.html"
  content_type           = "text/html"
  cache_control          = "no-store"
  content_md5            = filemd5("callback.html")
}

resource "azurerm_storage_blob" "favicon" {
  name                   = "favicon.ico"
  storage_account_name   = data.azurerm_storage_account.web.name
  storage_container_name = "$web"
  type                   = "Block"
  source                 = "favicon.ico"
  content_type           = "image/x-icon"
  cache_control          = "no-store"
  content_md5            = filemd5("favicon.ico")
}

resource "azurerm_storage_blob" "config" {
  name                   = "config.json"
  storage_account_name   = data.azurerm_storage_account.web.name
  storage_container_name = "$web"
  type                   = "Block"
  source                 = "config.json"
  content_type           = "application/json"
  cache_control          = "no-store"
  content_md5            = filemd5("config.json")
}

output "website_url" {
  value = data.azurerm_storage_account.web.primary_web_endpoint
}
