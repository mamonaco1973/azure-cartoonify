# ================================================================================
# Storage Accounts
# web    — static website hosting for the SPA ($web container)
# media  — private blob storage for originals/ and cartoons/
#
# Web storage lives here (not in 03-webapp) so its URL is known before the
# Entra External ID app registration redirect URI is written.
# ================================================================================

# ------------------------------------------------------------------------------
# Web storage (SPA hosting)
# ------------------------------------------------------------------------------
resource "azurerm_storage_account" "web" {
  name                     = "cartoonweb${random_id.suffix.hex}"
  resource_group_name      = azurerm_resource_group.cartoonify.name
  location                 = azurerm_resource_group.cartoonify.location
  account_tier             = "Standard"
  account_replication_type = "LRS"
  min_tls_version          = "TLS1_2"
}

resource "azurerm_storage_account_static_website" "web" {
  storage_account_id = azurerm_storage_account.web.id
  index_document     = "index.html"
}

# ------------------------------------------------------------------------------
# Media storage (originals + cartoons, private)
# ------------------------------------------------------------------------------
resource "azurerm_storage_account" "media" {
  name                     = "cartoonmedia${random_id.suffix.hex}"
  resource_group_name      = azurerm_resource_group.cartoonify.name
  location                 = azurerm_resource_group.cartoonify.location
  account_tier             = "Standard"
  account_replication_type = "LRS"
  min_tls_version          = "TLS1_2"

  # CORS allows the browser to PUT directly to the SAS upload URL
  blob_properties {
    cors_rule {
      allowed_headers    = ["*"]
      allowed_methods    = ["PUT", "GET"]
      allowed_origins    = ["*"]
      exposed_headers    = ["ETag"]
      max_age_in_seconds = 300
    }
  }
}

resource "azurerm_storage_container" "originals" {
  name                  = "originals"
  storage_account_id    = azurerm_storage_account.media.id
  container_access_type = "private"
}

resource "azurerm_storage_container" "cartoons" {
  name                  = "cartoons"
  storage_account_id    = azurerm_storage_account.media.id
  container_access_type = "private"
}

# ------------------------------------------------------------------------------
# Lifecycle: delete originals after 7 days, cartoons after 7 days
# Mirrors S3 lifecycle in aws-cartoonify
# ------------------------------------------------------------------------------
resource "azurerm_storage_management_policy" "media_lifecycle" {
  storage_account_id = azurerm_storage_account.media.id

  rule {
    name    = "expire-originals"
    enabled = true
    filters {
      prefix_match = ["originals/"]
      blob_types   = ["blockBlob"]
    }
    actions {
      base_blob {
        delete_after_days_since_modification_greater_than = 7
      }
    }
  }

  rule {
    name    = "expire-cartoons"
    enabled = true
    filters {
      prefix_match = ["cartoons/"]
      blob_types   = ["blockBlob"]
    }
    actions {
      base_blob {
        delete_after_days_since_modification_greater_than = 7
      }
    }
  }
}
