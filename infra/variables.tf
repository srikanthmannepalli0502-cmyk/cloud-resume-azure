variable "subscription_id" {
  description = "Azure subscription ID to deploy into."
  type        = string
}

variable "resource_group_name" {
  description = "Existing resource group (created by scripts/bootstrap.ps1)."
  type        = string
  default     = "rg-cloudresume"
}

variable "prefix" {
  description = "Short lowercase name used in resource names. Max 11 letters/digits (storage account names are limited to 24 characters)."
  type        = string
  default     = "cloudresume"

  validation {
    condition     = can(regex("^[a-z0-9]{1,11}$", var.prefix))
    error_message = "prefix must be 1-11 lowercase letters or digits."
  }
}

variable "cosmos_location" {
  description = "Region for Cosmos DB. Kept separate because popular regions (e.g. eastus) often run out of Cosmos DB capacity for new accounts."
  type        = string
  default     = "eastus2"
}

variable "enable_front_door" {
  description = "Create Azure Front Door Standard for HTTPS + CDN. Costs about $35/month while it exists."
  type        = bool
  default     = false
}

variable "custom_domain" {
  description = "Custom domain for the site, e.g. resume.example.com. Requires enable_front_door = true. Leave empty to skip."
  type        = string
  default     = ""
}

variable "extra_cors_origins" {
  description = "Additional origins allowed to call the API, e.g. [\"http://localhost:5500\"] for local testing."
  type        = list(string)
  default     = []
}

variable "tags" {
  type = map(string)
  default = {
    project = "cloud-resume-challenge"
  }
}
