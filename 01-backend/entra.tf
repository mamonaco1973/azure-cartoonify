# Entra External ID app registration for the cartoonify SPA.
# The redirect URI points at the web storage account from storage.tf,
# so that resource is provisioned before this one.
resource "azuread_application" "cartoonify" {
  display_name = "cartoonify-app"

  # External ID tenants require v2 — v1 tokens are rejected with 400
  api {
    requested_access_token_version = 2
  }

  # SPA platform: authorization code + PKCE, no client secret
  single_page_application {
    redirect_uris = [
      "${azurerm_storage_account.web.primary_web_endpoint}callback.html"
    ]
  }
}

# Service principal is required for the app to appear in the user flow
# Applications picker so self-service sign-up can be enabled
resource "azuread_service_principal" "cartoonify" {
  client_id = azuread_application.cartoonify.client_id
}
