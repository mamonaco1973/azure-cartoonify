# ================================================================================
# Azure OpenAI — image generation backend
# Replaces AWS Bedrock. The Function App worker calls the gpt-image-1
# images.edit endpoint, authenticated via managed identity (no API key).
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

# gpt-image-1 supports image editing (images.edit) — input image + text prompt
# → cartoonified output. This is the Azure-native replacement for
# Bedrock stable-image-control-structure.
resource "azurerm_cognitive_deployment" "gpt_image_1" {
  name                 = "gpt-image-1"
  cognitive_account_id = azurerm_cognitive_account.openai.id

  model {
    format  = "OpenAI"
    name    = "gpt-image-1"
    version = "2025-04-15"
  }

  sku {
    # Standard quota pool — GlobalStandard requires subscription allowlisting
    name     = "Standard"
    capacity = 1
  }
}
