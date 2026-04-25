terraform {
  required_providers {
    azurerm = {
      source  = "hashicorp/azurerm"
      version = "~> 4.0"
    }
    azuread = {
      source  = "hashicorp/azuread"
      version = "~> 3.0"
    }
    random = {
      source  = "hashicorp/random"
      version = "~> 3.0"
    }
  }
}

provider "azurerm" {
  features {
    resource_group {
      prevent_deletion_if_contains_resources = false
    }
  }
}

# Points at the Entra External tenant, not the main subscription tenant.
# Requires a service principal registered IN the Entra External tenant with
# Application.ReadWrite.All on Microsoft Graph.
provider "azuread" {
  tenant_id     = var.entra_tenant_id
  client_id     = var.entra_sp_client_id
  client_secret = var.entra_sp_client_secret
}

resource "random_id" "suffix" {
  byte_length = 4
}

resource "azurerm_resource_group" "notes" {
  name     = "notes-entra-rg"
  location = var.location
}
