# ================================================================================
# Azure OpenAI — image generation backend
# DALL-E 2 supports images.edit() with an input image, making it suitable for
# cartoonification. gpt-image-1 requires subscription allowlisting in Azure.
# ================================================================================

resource "random_string" "openai_suffix" {
  length  = 8
  special = false
  upper   = false
}

resource "azurerm_cognitive_account" "openai" {
  name                  = "cartoonify-openai-${random_string.openai_suffix.result}"
  resource_group_name   = azurerm_resource_group.cartoonify.name
  location              = azurerm_resource_group.cartoonify.location
  kind                  = "AIServices"
  sku_name              = "S0"
  custom_subdomain_name = "cartoonify-openai-${random_string.openai_suffix.result}"
}

# DALL-E 2 uses images.edit() — input image + prompt → cartoonified output.
# Standard SKU is available without subscription allowlisting.
resource "azurerm_cognitive_deployment" "image_model" {
  name                 = "dall-e-2"
  cognitive_account_id = azurerm_cognitive_account.openai.id

  model {
    format = "OpenAI"
    name   = "dall-e-2"
  }

  sku {
    name     = "Standard"
    capacity = 1
  }
}
