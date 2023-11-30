output "key_vault" {
  value = azurerm_key_vault.kv
}

output "key_vault_private_endpoint" {
  value = azurerm_private_endpoint.kv_pe
}
