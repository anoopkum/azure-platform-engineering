output "aks_cluster_name" {
  value = module.aks.cluster_name
}

output "acr_login_server" {
  value = module.acr.login_server
}

output "aks_oidc_issuer_url" {
  value = module.aks.oidc_issuer_url
}

output "key_vault_name" {
  value = module.keyvault.key_vault_name
}

output "external_secrets_wi_client_id" {
  value = module.workload_identity_external_secrets.client_id
}
