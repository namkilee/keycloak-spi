output "scope_ids" {
  value = {
    for client_key, client in var.clients :
    client_key => {
      for scope_key, scope in client.scopes :
      scope_key => keycloak_openid_client_scope.scopes["${client_key}.${scope_key}"].id
    }
  }
}

output "scope_names" {
  value = {
    for client_key, client in var.clients :
    client_key => {
      for scope_key, scope in client.scopes :
      scope_key => keycloak_openid_client_scope.scopes["${client_key}.${scope_key}"].name
    }
  }
}
