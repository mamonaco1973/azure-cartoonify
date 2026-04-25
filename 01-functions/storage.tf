# Web hosting storage — lives here (not in 02-webapp) so the URL is known
# before the Entra External ID app registration redirect URI is configured.
resource "azurerm_storage_account" "web" {
  name                     = "notesentraweb${random_id.suffix.hex}"
  resource_group_name      = azurerm_resource_group.notes.name
  location                 = azurerm_resource_group.notes.location
  account_tier             = "Standard"
  account_replication_type = "LRS"
}

resource "azurerm_storage_account_static_website" "web" {
  storage_account_id = azurerm_storage_account.web.id
  index_document     = "index.html"
}
