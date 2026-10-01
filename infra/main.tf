data "azurerm_resource_group" "main" {
  name = var.resource_group_name
}

# Storage account, Cosmos DB and Function App names must be globally unique.
resource "random_string" "suffix" {
  length  = 6
  upper   = false
  special = false
}

locals {
  location = data.azurerm_resource_group.main.location
  rg       = data.azurerm_resource_group.main.name
  suffix   = random_string.suffix.result

  custom_domain_enabled = var.enable_front_door && var.custom_domain != ""

  cors_origins = concat(
    [trimsuffix(azurerm_storage_account.site.primary_web_endpoint, "/")],
    var.enable_front_door ? ["https://${azurerm_cdn_frontdoor_endpoint.site[0].host_name}"] : [],
    var.custom_domain != "" ? ["https://${var.custom_domain}"] : [],
    var.extra_cors_origins,
  )
}

# ---------------------------------------------------------------------------
# Frontend: static website hosting
# ---------------------------------------------------------------------------

resource "azurerm_storage_account" "site" {
  name                     = "st${var.prefix}web${local.suffix}"
  resource_group_name      = local.rg
  location                 = local.location
  account_tier             = "Standard"
  account_replication_type = "LRS"
  min_tls_version          = "TLS1_2"
  tags                     = var.tags
}

resource "azurerm_storage_account_static_website" "site" {
  storage_account_id = azurerm_storage_account.site.id
  index_document     = "index.html"
  error_404_document = "404.html"
}

# ---------------------------------------------------------------------------
# Database: Cosmos DB (serverless, pay per request)
# ---------------------------------------------------------------------------

resource "azurerm_cosmosdb_account" "db" {
  name                = "cosmos-${var.prefix}-${local.suffix}"
  resource_group_name = local.rg
  location            = var.cosmos_location
  offer_type          = "Standard"
  kind                = "GlobalDocumentDB"
  tags                = var.tags

  capabilities {
    name = "EnableServerless"
  }

  consistency_policy {
    consistency_level = "Session"
  }

  geo_location {
    location          = var.cosmos_location
    failover_priority = 0
  }
}

resource "azurerm_cosmosdb_sql_database" "resume" {
  name                = "resume"
  resource_group_name = local.rg
  account_name        = azurerm_cosmosdb_account.db.name
}

resource "azurerm_cosmosdb_sql_container" "counters" {
  name                = "counters"
  resource_group_name = local.rg
  account_name        = azurerm_cosmosdb_account.db.name
  database_name       = azurerm_cosmosdb_sql_database.resume.name
  partition_key_paths = ["/id"]
}

# Let the Function App's managed identity read/write data (no keys in app settings).
resource "azurerm_cosmosdb_sql_role_assignment" "function_data_contributor" {
  resource_group_name = local.rg
  account_name        = azurerm_cosmosdb_account.db.name
  # Built-in "Cosmos DB Built-in Data Contributor" role.
  role_definition_id = "${azurerm_cosmosdb_account.db.id}/sqlRoleDefinitions/00000000-0000-0000-0000-000000000002"
  principal_id       = azurerm_function_app_flex_consumption.api.identity[0].principal_id
  scope              = azurerm_cosmosdb_account.db.id
}

# ---------------------------------------------------------------------------
# API: Azure Functions (Flex Consumption, Python)
# ---------------------------------------------------------------------------

resource "azurerm_storage_account" "func" {
  name                     = "st${var.prefix}fn${local.suffix}"
  resource_group_name      = local.rg
  location                 = local.location
  account_tier             = "Standard"
  account_replication_type = "LRS"
  min_tls_version          = "TLS1_2"
  tags                     = var.tags
}

resource "azurerm_storage_container" "deployments" {
  name                  = "deployments"
  storage_account_id    = azurerm_storage_account.func.id
  container_access_type = "private"
}

resource "azurerm_log_analytics_workspace" "main" {
  name                = "log-${var.prefix}-${local.suffix}"
  resource_group_name = local.rg
  location            = local.location
  sku                 = "PerGB2018"
  retention_in_days   = 30
  tags                = var.tags
}

resource "azurerm_application_insights" "main" {
  name                = "appi-${var.prefix}-${local.suffix}"
  resource_group_name = local.rg
  location            = local.location
  workspace_id        = azurerm_log_analytics_workspace.main.id
  application_type    = "web"
  tags                = var.tags
}

resource "azurerm_service_plan" "api" {
  name                = "asp-${var.prefix}-${local.suffix}"
  resource_group_name = local.rg
  location            = local.location
  os_type             = "Linux"
  sku_name            = "FC1"
  tags                = var.tags
}

resource "azurerm_function_app_flex_consumption" "api" {
  name                = "func-${var.prefix}-${local.suffix}"
  resource_group_name = local.rg
  location            = local.location
  service_plan_id     = azurerm_service_plan.api.id
  tags                = var.tags

  storage_container_type      = "blobContainer"
  storage_container_endpoint  = "${azurerm_storage_account.func.primary_blob_endpoint}${azurerm_storage_container.deployments.name}"
  storage_authentication_type = "StorageAccountConnectionString"
  storage_access_key          = azurerm_storage_account.func.primary_access_key

  runtime_name           = "python"
  runtime_version        = "3.12"
  maximum_instance_count = 40
  instance_memory_in_mb  = 2048

  identity {
    type = "SystemAssigned"
  }

  app_settings = {
    COSMOS_ENDPOINT  = azurerm_cosmosdb_account.db.endpoint
    COSMOS_DATABASE  = azurerm_cosmosdb_sql_database.resume.name
    COSMOS_CONTAINER = azurerm_cosmosdb_sql_container.counters.name
  }

  site_config {
    application_insights_connection_string = azurerm_application_insights.main.connection_string

    cors {
      allowed_origins = local.cors_origins
    }
  }
}
