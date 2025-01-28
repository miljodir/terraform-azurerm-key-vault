data "azurerm_client_config" "current" {}

locals {
  key_vault_name                = var.key_vault_name != null ? var.key_vault_name : "${var.rg_name}${var.unique}-kv"
  public_network_access_enabled = local.allow_known_pips ? true : var.public_network_access_enabled ? true : false
  allow_known_pips              = split("-", var.rg_name)[0] == "d" ? true : false
}

module "network_vars" {
  # private module used for public IP whitelisting
  count  = local.public_network_access_enabled == true ? 1 : 0
  source = "git@github.com:miljodir/cp-shared.git//modules/public_nw_ips?ref=public_nw_ips/v1"
}

resource "azurerm_key_vault" "kv" {
  location                        = var.location
  name                            = local.key_vault_name
  resource_group_name             = var.rg_name
  sku_name                        = var.sku_name
  tenant_id                       = data.azurerm_client_config.current.tenant_id
  enable_rbac_authorization       = var.enable_rbac_authorization
  purge_protection_enabled        = var.purge_protection_enabled #tfsec:ignore:azure-keyvault-no-purge
  soft_delete_retention_days      = var.soft_delete_retention_days
  enabled_for_deployment          = var.enabled_for_deployment
  enabled_for_disk_encryption     = var.enabled_for_disk_encryption
  enabled_for_template_deployment = var.enabled_for_template_deployment
  public_network_access_enabled   = local.public_network_access_enabled

  network_acls {
    default_action             = var.network_acls.default_action != null ? var.network_acls.default_action : "Deny"
    bypass                     = var.network_acls.bypass != null ? var.network_acls.bypass : "None"
    ip_rules                   = local.allow_known_pips ? concat(values(module.network_vars[0].known_public_ips), var.network_acls.ip_rules) : var.network_acls.ip_rules
    virtual_network_subnet_ids = var.network_acls.subnet_ids != null ? var.network_acls.subnet_ids : []
  }
}

resource "azurerm_private_endpoint" "kv_pe" {
  count               = var.enable_private_endpoint == true && var.subnet_id != null ? 1 : 0
  location            = azurerm_key_vault.kv.location
  name                = "${azurerm_key_vault.kv.name}-pe"
  resource_group_name = azurerm_key_vault.kv.resource_group_name
  subnet_id           = var.subnet_id

  private_service_connection {
    name                           = azurerm_key_vault.kv.name
    private_connection_resource_id = azurerm_key_vault.kv.id
    subresource_names              = ["vault"]
    is_manual_connection           = false
  }

  lifecycle {
    ignore_changes = [
      tags,
      private_dns_zone_group,
    ]
  }
}

resource "azurerm_private_dns_a_record" "kv_dns" {
  count               = var.enable_private_endpoint == true && var.subnet_id != null ? 1 : 0
  name                = azurerm_key_vault.kv.name
  records             = [azurerm_private_endpoint.kv_pe[0].private_service_connection[0].private_ip_address]
  resource_group_name = var.dns_rg_name
  ttl                 = 600
  zone_name           = "privatelink.vaultcore.azure.net"

  provider = azurerm.p-dns

  lifecycle {
    ignore_changes = [
      ttl,
      tags,
    ]
  }
}

