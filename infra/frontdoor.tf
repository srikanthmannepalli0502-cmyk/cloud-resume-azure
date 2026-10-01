# Azure Front Door Standard: HTTPS on a custom domain + global CDN.
# Only created when enable_front_door = true (about $35/month while it exists).

resource "azurerm_cdn_frontdoor_profile" "fd" {
  count               = var.enable_front_door ? 1 : 0
  name                = "afd-${var.prefix}-${local.suffix}"
  resource_group_name = local.rg
  sku_name            = "Standard_AzureFrontDoor"
  tags                = var.tags
}

resource "azurerm_cdn_frontdoor_endpoint" "site" {
  count                    = var.enable_front_door ? 1 : 0
  name                     = "${var.prefix}-${local.suffix}"
  cdn_frontdoor_profile_id = azurerm_cdn_frontdoor_profile.fd[0].id
  tags                     = var.tags
}

resource "azurerm_cdn_frontdoor_origin_group" "site" {
  count                    = var.enable_front_door ? 1 : 0
  name                     = "static-site"
  cdn_frontdoor_profile_id = azurerm_cdn_frontdoor_profile.fd[0].id

  load_balancing {}
}

resource "azurerm_cdn_frontdoor_origin" "site" {
  count                         = var.enable_front_door ? 1 : 0
  name                          = "storage-web"
  cdn_frontdoor_origin_group_id = azurerm_cdn_frontdoor_origin_group.site[0].id

  enabled                        = true
  host_name                      = azurerm_storage_account.site.primary_web_host
  origin_host_header             = azurerm_storage_account.site.primary_web_host
  http_port                      = 80
  https_port                     = 443
  certificate_name_check_enabled = true
}

resource "azurerm_cdn_frontdoor_custom_domain" "site" {
  count                    = local.custom_domain_enabled ? 1 : 0
  name                     = replace(var.custom_domain, ".", "-")
  cdn_frontdoor_profile_id = azurerm_cdn_frontdoor_profile.fd[0].id
  host_name                = var.custom_domain

  tls {
    certificate_type = "ManagedCertificate"
  }
}

resource "azurerm_cdn_frontdoor_route" "site" {
  count                         = var.enable_front_door ? 1 : 0
  name                          = "default"
  cdn_frontdoor_endpoint_id     = azurerm_cdn_frontdoor_endpoint.site[0].id
  cdn_frontdoor_origin_group_id = azurerm_cdn_frontdoor_origin_group.site[0].id
  cdn_frontdoor_origin_ids      = [azurerm_cdn_frontdoor_origin.site[0].id]

  cdn_frontdoor_custom_domain_ids = local.custom_domain_enabled ? [azurerm_cdn_frontdoor_custom_domain.site[0].id] : []
  link_to_default_domain          = true

  patterns_to_match      = ["/*"]
  supported_protocols    = ["Http", "Https"]
  https_redirect_enabled = true
  forwarding_protocol    = "HttpsOnly"

  cache {
    query_string_caching_behavior = "IgnoreQueryString"
    compression_enabled           = true
    content_types_to_compress     = ["text/html", "text/css", "application/javascript", "text/javascript"]
  }
}

resource "azurerm_cdn_frontdoor_custom_domain_association" "site" {
  count                          = local.custom_domain_enabled ? 1 : 0
  cdn_frontdoor_custom_domain_id = azurerm_cdn_frontdoor_custom_domain.site[0].id
  cdn_frontdoor_route_ids        = [azurerm_cdn_frontdoor_route.site[0].id]
}
