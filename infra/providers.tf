terraform {
  required_version = ">= 1.9"

  required_providers {
    azurerm = {
      source  = "hashicorp/azurerm"
      version = "~> 4.30"
    }
    random = {
      source  = "hashicorp/random"
      version = "~> 3.6"
    }
  }

  # Remote state in the storage account created by scripts/bootstrap.ps1.
  # Values come from backend.hcl locally (`terraform init -backend-config=backend.hcl`)
  # or from -backend-config flags in GitHub Actions.
  backend "azurerm" {
    use_azuread_auth = true
  }
}

provider "azurerm" {
  features {}
  subscription_id = var.subscription_id

  # The GitHub identity only has rights on the resource group, not the whole
  # subscription, so it can't register providers. bootstrap.ps1 registers them.
  resource_provider_registrations = "none"
}
