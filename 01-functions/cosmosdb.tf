resource "azurerm_cosmosdb_account" "notes" {
  name                = "notes-b2c-cosmos-${random_id.suffix.hex}"
  location            = azurerm_resource_group.notes.location
  resource_group_name = azurerm_resource_group.notes.name
  offer_type          = "Standard"
  kind                = "GlobalDocumentDB"

  consistency_policy {
    consistency_level = "Session"
  }

  geo_location {
    location          = azurerm_resource_group.notes.location
    failover_priority = 0
  }
}

resource "azurerm_cosmosdb_sql_database" "notes" {
  name                = "notes"
  resource_group_name = azurerm_resource_group.notes.name
  account_name        = azurerm_cosmosdb_account.notes.name
}

resource "azurerm_cosmosdb_sql_container" "notes" {
  name                = "notes"
  resource_group_name = azurerm_resource_group.notes.name
  account_name        = azurerm_cosmosdb_account.notes.name
  database_name       = azurerm_cosmosdb_sql_database.notes.name
  partition_key_paths = ["/owner"]
  throughput          = 400
}
