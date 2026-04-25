terraform {
  required_providers {
    azurerm = {
      source  = "hashicorp/azurerm"
      version = "~> 4.0"
    }
  }
}

provider "azurerm" {
  features {}
}

# The storage account is created by 01-functions (so its URL is known before
# the Entra app registration redirect URI is written). This module only uploads
# the built files into the existing $web container.
variable "web_storage_name" {
  description = "Name of the storage account created by 01-functions"
  type        = string
}
