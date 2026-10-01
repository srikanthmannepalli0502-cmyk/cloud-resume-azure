output "site_storage_account" {
  description = "Set as the SITE_STORAGE_ACCOUNT GitHub variable."
  value       = azurerm_storage_account.site.name
}

output "function_app_name" {
  description = "Set as the FUNCTION_APP_NAME GitHub variable."
  value       = azurerm_function_app_flex_consumption.api.name
}

output "api_url" {
  description = "Set as the API_URL GitHub variable."
  value       = "https://${azurerm_function_app_flex_consumption.api.default_hostname}/api/visitors"
}

output "storage_website_url" {
  value = azurerm_storage_account.site.primary_web_endpoint
}

output "front_door_url" {
  value = var.enable_front_door ? "https://${azurerm_cdn_frontdoor_endpoint.site[0].host_name}" : null
}

output "front_door_profile_name" {
  description = "Set as the FRONT_DOOR_PROFILE GitHub variable (enables cache purge on deploy)."
  value       = var.enable_front_door ? azurerm_cdn_frontdoor_profile.fd[0].name : null
}

output "front_door_endpoint_name" {
  description = "Set as the FRONT_DOOR_ENDPOINT GitHub variable."
  value       = var.enable_front_door ? azurerm_cdn_frontdoor_endpoint.site[0].name : null
}

output "custom_domain_cname_target" {
  description = "Create a CNAME record from your custom domain to this host."
  value       = local.custom_domain_enabled ? azurerm_cdn_frontdoor_endpoint.site[0].host_name : null
}

output "custom_domain_validation_txt" {
  description = "Create a TXT record named _dnsauth.<your subdomain> with this value to validate the domain."
  value       = local.custom_domain_enabled ? azurerm_cdn_frontdoor_custom_domain.site[0].validation_token : null
}
