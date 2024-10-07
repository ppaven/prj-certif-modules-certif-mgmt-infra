locals {
    sa_name  = lower("${var.company_trig}${var.env}${var.service_name}sa01")
}

resource "azurerm_storage_account" "sa" {
  name                      = local.sa_name
  resource_group_name       = azurerm_resource_group.certificates.name
  location                  = var.location
  account_kind              = var.account_kind
  account_tier              = var.account_tier
  account_replication_type  = var.account_replication_type

  https_traffic_only_enabled = var.force_https
  allow_nested_items_to_be_public = false

  tags = var.tags
}

data "azurerm_storage_account" "sa" {
  name                      = azurerm_storage_account.sa.name
  resource_group_name       = azurerm_resource_group.certificates.name
}

resource "azurerm_storage_container" "sacont" {
  name                 = "letsencrypt"
  storage_account_name = azurerm_storage_account.sa.name
}

resource "azurerm_role_assignment" "sbdc_current_user" {
  scope                = azurerm_storage_account.sa.id
  role_definition_name = "Storage Blob Data Contributor"
  principal_id         = data.azurerm_client_config.current.object_id
}

resource "azurerm_role_assignment" "sbdc_automation" {
    scope                 = azurerm_storage_account.sa.id
    role_definition_name  = "Storage Blob Data Owner"
    principal_id          = azurerm_automation_account.cert_aa.identity[0].principal_id
}
