
################
# Variables for naming convention

#---------
# Compagny trigram
variable company_trig {
  default = "AZC"
}
#---------
# Environment
variable env {
    default = "POC"
}

#---------
# Short Service/Project name 
variable service_name {
  type        = string
  default  = "CERT"
}

################
# Souscription
variable subscription_id {} # = Environment variable TF_VAR_subscription_id

################
# Location
variable location {
  default = "francecentral"
}

################
# Automation account module
variable modules {
  type = map
  description = "Map of automation modules"
  default = {
      "names" = "ACME-PS"
      # "names" = "ACME-PS,Az,Az.Accounts,Az.ApiManagement,Az.Network"
      "uri_base" = "https://psg-prod-eastus.azureedge.net/packages/"
      "files" = "acme-ps.1.5.9.nupkg"
      # "files" = "acme-ps.1.5.9.nupkg,az.12.3.0.nupkg,az.accounts.3.0.4.nupkg,az.apimanagement.4.0.4.nupkg,az.network.7.8.1.nupkg"
  }
}

################
# Keyvault parameter
variable soft_delete_retention_days {
  type        = string
  default     = "7"
}

################
# Storage Account for LetEncrypt context backup

variable "account_kind" {
  default = "StorageV2"
}

variable "account_tier" {
  default = "Standard"
}

variable "account_replication_type" {
  default = "LRS"
}

variable "force_https" {
  default = true
}

################
# Runbooks

variable runbook_create {
  default = "CreateCert-LetsEncrypt"
}
variable runbook_renew {
  default = "Renew-LetsEncrypt"
}
variable runbook_update {
  default = "UpdateCert-LetsEncrypt"
}

################
# Tags

variable tags {
    type        = map(string)
}
