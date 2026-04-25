# ================================================================================
# Cosmos DB — job state store
# Replaces AWS DynamoDB. Partition key /owner mirrors DynamoDB PK=owner.
# TTL on the container matches the 7-day retention window.
# ================================================================================

resource "azurerm_cosmosdb_account" "cartoonify" {
  name                = "cosmos-cartoonify-${random_id.suffix.hex}"
  location            = azurerm_resource_group.cartoonify.location
  resource_group_name = azurerm_resource_group.cartoonify.name
  offer_type          = "Standard"
  kind                = "GlobalDocumentDB"

  consistency_policy {
    consistency_level = "Session"
  }

  geo_location {
    location          = azurerm_resource_group.cartoonify.location
    failover_priority = 0
  }
}

resource "azurerm_cosmosdb_sql_database" "cartoonify" {
  name                = "cartoonify"
  resource_group_name = azurerm_resource_group.cartoonify.name
  account_name        = azurerm_cosmosdb_account.cartoonify.name
}

resource "azurerm_cosmosdb_sql_container" "jobs" {
  name                = "jobs"
  resource_group_name = azurerm_resource_group.cartoonify.name
  account_name        = azurerm_cosmosdb_account.cartoonify.name
  database_name       = azurerm_cosmosdb_sql_database.cartoonify.name
  partition_key_paths = ["/owner"]

  # -1 means no default TTL; individual items carry a "ttl" field (7 days).
  # The container must have TTL enabled (value != -1 disables it entirely;
  # set to a large number and let per-item ttl override it)
  default_ttl = 604800 # 7 days — matches JOB_TTL_SECONDS in common.py

  throughput = 400

  indexing_policy {
    indexing_mode = "consistent"

    included_path { path = "/*" }
    excluded_path { path = "/\"_etag\"/?" }
  }

  lifecycle {
    ignore_changes = [indexing_policy]
  }
}

# ================================================================================
# Cosmos DB RBAC — Function App managed identity
# Custom role scoped to the account so the Function App can read/write jobs.
# ================================================================================

resource "azurerm_cosmosdb_sql_role_definition" "func_role" {
  name                = "CartoonifyFuncRole"
  resource_group_name = azurerm_resource_group.cartoonify.name
  account_name        = azurerm_cosmosdb_account.cartoonify.name
  type                = "CustomRole"
  assignable_scopes   = [azurerm_cosmosdb_account.cartoonify.id]

  permissions {
    data_actions = [
      "Microsoft.DocumentDB/databaseAccounts/readMetadata",
      "Microsoft.DocumentDB/databaseAccounts/sqlDatabases/containers/*",
      "Microsoft.DocumentDB/databaseAccounts/sqlDatabases/containers/items/*",
    ]
  }
}
