mock_provider "azurerm" {
  mock_data "azurerm_client_config" {
    defaults = {
      tenant_id = "00000000-0000-0000-0000-000000000000"
    }
  }

  # Generated mock IDs are random strings; resources that parse IDs need a real-looking one.
  mock_resource "azurerm_key_vault" {
    defaults = {
      id = "/subscriptions/00000000-0000-0000-0000-000000000000/resourceGroups/p-test-rg/providers/Microsoft.KeyVault/vaults/kv-test"
    }
  }
}

# The internal public IP module is replaced with documentation-range addresses.
override_module {
  target = module.network_vars
  outputs = {
    known_public_ips = {
      office = "192.0.2.10"
      vpn    = "198.51.100.20"
    }
  }
}

variables {
  rg_name   = "p-test-rg"
  unique    = "abc123"
  subnet_id = "/subscriptions/00000000-0000-0000-0000-000000000000/resourceGroups/rg-network/providers/Microsoft.Network/virtualNetworks/vnet-test/subnets/snet-pe"
}

run "defaults" {
  command = plan

  assert {
    condition     = azurerm_key_vault.kv.name == "p-test-rgabc123-kv"
    error_message = "Name should be derived from rg_name and unique."
  }

  assert {
    condition     = azurerm_key_vault.kv.location == "norwayeast"
    error_message = "Location should default to norwayeast."
  }

  assert {
    condition     = azurerm_key_vault.kv.sku_name == "standard"
    error_message = "SKU should default to standard."
  }

  assert {
    condition     = azurerm_key_vault.kv.rbac_authorization_enabled == true
    error_message = "RBAC authorization should be enabled by default."
  }

  assert {
    condition     = azurerm_key_vault.kv.soft_delete_retention_days == 90
    error_message = "Soft delete retention should default to 90 days."
  }

  assert {
    condition     = azurerm_key_vault.kv.tenant_id == "00000000-0000-0000-0000-000000000000"
    error_message = "Tenant ID should come from the current client config."
  }

  assert {
    condition     = azurerm_key_vault.kv.network_acls[0].default_action == "Deny"
    error_message = "Network ACLs should deny by default."
  }

  assert {
    condition     = azurerm_key_vault.kv.network_acls[0].bypass == "None"
    error_message = "Network ACL bypass should default to None."
  }

  assert {
    condition     = length(azurerm_key_vault.kv.network_acls[0].ip_rules) == 0
    error_message = "Known public IPs must not be allowed outside development resource groups."
  }

  assert {
    condition     = length(azurerm_private_endpoint.kv_pe) == 1
    error_message = "A private endpoint should be created when subnet_id is set."
  }
}

run "private_endpoint_wiring" {
  command = apply

  assert {
    condition     = azurerm_private_endpoint.kv_pe[0].name == "p-test-rgabc123-kv-pe"
    error_message = "Private endpoint name should be '<vault name>-pe'."
  }

  assert {
    condition     = azurerm_private_endpoint.kv_pe[0].private_service_connection[0].private_connection_resource_id == azurerm_key_vault.kv.id
    error_message = "Private endpoint should connect to the key vault."
  }

  assert {
    condition     = azurerm_private_endpoint.kv_pe[0].private_service_connection[0].subresource_names == tolist(["vault"])
    error_message = "Private endpoint should target the 'vault' subresource."
  }

  assert {
    condition     = output.key_vault.id == azurerm_key_vault.kv.id
    error_message = "key_vault output should expose the key vault."
  }
}

run "no_private_endpoint_without_subnet" {
  command = plan

  variables {
    subnet_id = null
  }

  assert {
    condition     = length(azurerm_private_endpoint.kv_pe) == 0
    error_message = "No private endpoint should be created without subnet_id."
  }
}

run "private_endpoint_can_be_disabled" {
  command = plan

  variables {
    enable_private_endpoint = false
  }

  assert {
    condition     = length(azurerm_private_endpoint.kv_pe) == 0
    error_message = "No private endpoint should be created when disabled."
  }
}

run "name_override" {
  command = plan

  variables {
    key_vault_name = "kv-custom-name"
  }

  assert {
    condition     = azurerm_key_vault.kv.name == "kv-custom-name"
    error_message = "key_vault_name should override the generated name."
  }
}

run "public_access_can_be_disabled_outside_dev" {
  command = plan

  variables {
    public_network_access_enabled = false
  }

  assert {
    condition     = azurerm_key_vault.kv.public_network_access_enabled == false
    error_message = "Public network access should be disabled when requested."
  }

  assert {
    condition     = length(module.network_vars) == 0
    error_message = "Known public IP lookup should not be used when public access is disabled."
  }
}

run "dev_resource_group_allows_known_public_ips" {
  command = plan

  variables {
    rg_name                       = "d-test-rg"
    public_network_access_enabled = false
    network_acls = {
      ip_rules = ["203.0.113.5"]
    }
  }

  assert {
    condition     = azurerm_key_vault.kv.public_network_access_enabled == true
    error_message = "Development resource groups should always enable public access for known IPs."
  }

  assert {
    condition     = toset(azurerm_key_vault.kv.network_acls[0].ip_rules) == toset(["192.0.2.10", "198.51.100.20", "203.0.113.5"])
    error_message = "Known public IPs should be merged with caller ip_rules in development."
  }
}

run "network_acls_overrides" {
  command = plan

  variables {
    network_acls = {
      default_action = "Allow"
      bypass         = "AzureServices"
      ip_rules       = ["203.0.113.0/24"]
      subnet_ids     = ["/subscriptions/00000000-0000-0000-0000-000000000000/resourceGroups/rg-network/providers/Microsoft.Network/virtualNetworks/vnet-test/subnets/snet-app"]
    }
  }

  assert {
    condition     = azurerm_key_vault.kv.network_acls[0].default_action == "Allow"
    error_message = "default_action should be configurable."
  }

  assert {
    condition     = azurerm_key_vault.kv.network_acls[0].bypass == "AzureServices"
    error_message = "bypass should be configurable."
  }

  assert {
    condition     = toset(azurerm_key_vault.kv.network_acls[0].ip_rules) == toset(["203.0.113.0/24"])
    error_message = "ip_rules should be passed through."
  }

  assert {
    condition     = length(azurerm_key_vault.kv.network_acls[0].virtual_network_subnet_ids) == 1
    error_message = "subnet_ids should be passed through."
  }
}

run "unique_must_be_six_characters" {
  command = plan

  variables {
    unique = "abc"
  }

  expect_failures = [var.unique]
}
