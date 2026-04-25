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

variable "web_storage_name" {
  description = "Name of the web storage account (from 01-backend outputs)"
  type        = string
}
