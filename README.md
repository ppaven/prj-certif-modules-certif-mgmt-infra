# certif-mgmt-infra terraform module

## description

Module to build resources for LetsEncrypt public certificate management

## vars

- Required:
  - **env** => (string)
  - **subscription_id** => (string)
  - **tags** => (map of string)
  
- Optional:
  - **location** => (string) default = "francecentral"
  - **company_trig** => (string) default = "AZC"
  - **service_name** => (string) default = "CERT"

## outputs


## usage

```
module "cert-infra" {
  source = "../modules/certif-mgmt-infra/"

  env               = "POC"
  subscription_id   = var.subscription_id
  location          = "northeurope"
  service_name      = "CERT"
  
  tags              = module.tags.datamap
}

