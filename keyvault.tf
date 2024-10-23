locals {
  keyvault_name = "${var.company_trig}-${var.env}-${var.service_name}-KVT01"
}


resource azurerm_key_vault "cert_vault" {
  name                = local.keyvault_name
  location            = azurerm_resource_group.certificates.location
  resource_group_name = azurerm_resource_group.certificates.name
  tenant_id = data.azurerm_client_config.current.tenant_id
  # soft_delete_retention_days  = var.soft_delete_retention_days
  # purge_protection_enabled    = true

  sku_name            = "standard"

  enabled_for_disk_encryption = true
  enabled_for_deployment = true
  enabled_for_template_deployment = true
  
  tags = var.tags
}

resource azurerm_key_vault_access_policy "cert_kv_policy1" {
  key_vault_id = azurerm_key_vault.cert_vault.id
  tenant_id = data.azurerm_client_config.current.tenant_id
  object_id = data.azurerm_client_config.current.object_id

  certificate_permissions = [
    "Create","Delete","DeleteIssuers",
    "Get","GetIssuers","Import","List",
    "ListIssuers","ManageContacts","ManageIssuers",
    "SetIssuers","Update","Backup","Purge","Recover","Restore"
  ]

  key_permissions = [
    "Backup","Create","Decrypt","Delete","Encrypt","Get",
    "Import","List","Purge","Recover","Restore","Sign",
    "UnwrapKey","Update","Verify","WrapKey",
  ]

  secret_permissions = [
    "Backup","Delete","Get","List","Purge","Recover","Restore","Set",
  ]

}

resource azurerm_key_vault_access_policy "cert_kv_policy2" {
  key_vault_id = azurerm_key_vault.cert_vault.id
  tenant_id = data.azurerm_client_config.current.tenant_id
  object_id = azurerm_automation_account.cert_aa.identity[0].principal_id

  certificate_permissions = [
    "Create","Delete","DeleteIssuers",
    "Get","GetIssuers","Import","List",
    "ListIssuers","ManageContacts","ManageIssuers",
    "SetIssuers","Update",
  ]

  key_permissions = [
    "Backup","Create","Decrypt","Delete","Encrypt","Get",
    "Import","List","Purge","Recover","Restore","Sign",
    "UnwrapKey","Update","Verify","WrapKey",
  ]

  secret_permissions = [
    "Backup","Delete","Get","List","Purge","Recover","Restore","Set",
  ]
} 
