data "azurerm_storage_account" "web" {
  name                = var.web_storage_name
  resource_group_name = "cartoonify-rg"
}

resource "azurerm_storage_blob" "index_html" {
  name                   = "index.html"
  storage_account_name   = data.azurerm_storage_account.web.name
  storage_container_name = "$web"
  type                   = "Block"
  source                 = "${path.module}/index.html"
  content_type           = "text/html"
  content_md5            = filemd5("${path.module}/index.html")
}

resource "azurerm_storage_blob" "callback_html" {
  name                   = "callback.html"
  storage_account_name   = data.azurerm_storage_account.web.name
  storage_container_name = "$web"
  type                   = "Block"
  source                 = "${path.module}/callback.html"
  content_type           = "text/html"
  content_md5            = filemd5("${path.module}/callback.html")
}

resource "azurerm_storage_blob" "config_json" {
  name                   = "config.json"
  storage_account_name   = data.azurerm_storage_account.web.name
  storage_container_name = "$web"
  type                   = "Block"
  source                 = "${path.module}/config.json"
  content_type           = "application/json"
  content_md5            = filemd5("${path.module}/config.json")

  # Prevent browsers from caching stale auth config
  cache_control = "no-store"
}

resource "azurerm_storage_blob" "favicon" {
  name                   = "favicon.ico"
  storage_account_name   = data.azurerm_storage_account.web.name
  storage_container_name = "$web"
  type                   = "Block"
  source                 = "${path.module}/favicon.ico"
  content_type           = "image/x-icon"
  content_md5            = filemd5("${path.module}/favicon.ico")
}

output "website_url" {
  value = data.azurerm_storage_account.web.primary_web_endpoint
}
