
terraform {
  required_version = "~> 1.5"
  required_providers {
    azurerm = {
      source                = "hashicorp/azurerm"
      version               = "~> 3.0"
      configuration_aliases = [azurerm.p-dns]
    }
  }
}