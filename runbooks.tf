data template_file "runbook_create" {
  template = file("${path.module}/runbooks/${var.runbook_create}.tpl.ps1")
  vars = {
    vault = local.keyvault_name
    subscription = data.azurerm_subscription.subs.display_name
    aa_name = azurerm_automation_account.cert_aa.name
    aa_rg = azurerm_resource_group.certificates.name
    sa_name = data.azurerm_storage_account.sa.name
  } 
}

data template_file "runbook_renew" {
  template = file("${path.module}/runbooks/${var.runbook_renew}.tpl.ps1")
  vars = {
    vault = local.keyvault_name
    subscription = data.azurerm_subscription.subs.display_name
    aa_name = azurerm_automation_account.cert_aa.name
    aa_rg = azurerm_resource_group.certificates.name
    sa_name = data.azurerm_storage_account.sa.name
  } 
}

resource azurerm_automation_runbook "runbook_create" {
  name                      = var.runbook_create
  location                  = azurerm_resource_group.certificates.location
  resource_group_name       = azurerm_resource_group.certificates.name
  automation_account_name   = azurerm_automation_account.cert_aa.name
  log_verbose               = "false"
  log_progress              = "false"
  description               = "LetEncrypt certificate creation Runbook "
  runbook_type              = "PowerShell"

  publish_content_link {
    uri = "https://raw.githubusercontent.com/Azure/azure-quickstart-templates/c4935ffb69246a6058eb24f54640f53f69d3ac9f/101-automation-runbook-getvms/Runbooks/Get-AzureVMTutorial.ps1"
  }

  content = data.template_file.runbook_create.rendered
}

resource azurerm_automation_runbook "runbook_renew" {
  name                      = var.runbook_renew
  location                  = azurerm_resource_group.certificates.location
  resource_group_name       = azurerm_resource_group.certificates.name
  automation_account_name   = azurerm_automation_account.cert_aa.name
  log_verbose               = "false"
  log_progress              = "false"
  description               = "LetEncrypt certificate renewal Runbook"
  runbook_type              = "PowerShell"

  publish_content_link {
    uri = "https://raw.githubusercontent.com/Azure/azure-quickstart-templates/c4935ffb69246a6058eb24f54640f53f69d3ac9f/101-automation-runbook-getvms/Runbooks/Get-AzureVMTutorial.ps1"
  }

  content = data.template_file.runbook_renew.rendered
}
