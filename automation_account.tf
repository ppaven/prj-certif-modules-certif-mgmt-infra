locals {
  aaa_name = lower("${var.company_trig}-${var.env}-${var.service_name}-AAA")
}

resource azurerm_automation_account "cert_aa" {
  name                = local.aaa_name
  location            = azurerm_resource_group.certificates.location
  resource_group_name = azurerm_resource_group.certificates.name

  sku_name            = "Basic"

  identity  {
    type = "SystemAssigned"
  }

  tags = var.tags
}

resource azurerm_automation_module "cert" {
  count = length(split(",", var.modules["names"]))

  name  = element(split(",", var.modules["names"]), count.index)
  resource_group_name = azurerm_resource_group.certificates.name
  automation_account_name = azurerm_automation_account.cert_aa.name

  module_link {
    uri = "${var.modules["uri_base"]}${element(split(",", var.modules["files"]), count.index)}"
  } 
}

resource "azurerm_role_assignment" "aa_role_subs" {
  scope                = data.azurerm_subscription.subs.id
  role_definition_name = "Contributor"
  principal_id         = azurerm_automation_account.cert_aa.identity[0].principal_id
}

