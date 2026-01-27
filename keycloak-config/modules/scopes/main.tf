locals {
  client_scopes = {
    for item in flatten([
      for client_key, client in var.clients : [
        for scope_key, scope in client.scopes : {
          key        = "${client_key}.${scope_key}"
          client_key = client_key
          client_id  = client.client_id
          scope_key  = scope_key
          description = scope.description
        }
      ]
    ]) : item.key => item
  }

  client_mappers = {
    for item in flatten([
      for client_key, client in var.clients : [
        for mapper in client.mappers : {
          key                 = "${client_key}.${mapper.name}"
          client_key          = client_key
          scope_resource_key  = "${client_key}.${mapper.scope}"
          name                = mapper.name
          protocol_mapper     = mapper.protocol_mapper
          config              = mapper.config
        }
      ]
    ]) : item.key => item
  }

  terms_scope_attributes = {
    for item in flatten([
      for client_key, client in var.clients : [
        for scope_key, scope in client.scopes : {
          key         = "${client_key}.${scope_key}"
          client_key  = client_key
          client_id   = client.client_id
          scope_key   = scope_key
          attributes  = try(scope.terms_attributes, null)
        }
      ]
    ]) : item.key => item
    if item.scope_key == "terms" && item.attributes != null
  }
}

resource "keycloak_openid_client_scope" "scopes" {
  for_each = local.client_scopes

  realm_id               = var.realm_id
  name                   = "${each.value.scope_key}-${each.value.client_id}"
  description            = each.value.description != "" ? each.value.description : "Client scope for ${each.value.scope_key}"
  consent_screen_text    = each.value.scope_key
  include_in_token_scope = true
}

resource "keycloak_generic_protocol_mapper" "value_transform" {
  for_each = local.client_mappers

  realm_id         = var.realm_id
  client_scope_id  = keycloak_openid_client_scope.scopes[each.value.scope_resource_key].id
  name             = each.value.name
  protocol         = "openid-connect"
  protocol_mapper  = each.value.protocol_mapper
  config           = each.value.config
}

resource "null_resource" "terms_scope_attributes" {
  for_each = local.terms_scope_attributes

  triggers = {
    scope_id    = keycloak_openid_client_scope.scopes[each.key].id
    tc_required = tostring(each.value.attributes.required)
    tc_version  = each.value.attributes.version
    tc_url      = coalesce(each.value.attributes.url, "")
    tc_template = coalesce(each.value.attributes.template, "")
    tc_key      = coalesce(each.value.attributes.key, "")
  }

  provisioner "local-exec" {
    interpreter = ["/bin/bash", "-lc"]
    command = <<EOT
set -euo pipefail

case "${var.kcadm_exec_mode}" in
  docker)
    if [ -z "${var.keycloak_container_name}" ]; then
      echo "keycloak_container_name is required when kcadm_exec_mode=docker" >&2
      exit 1
    fi
    KCADM_BASE=(docker exec "${var.keycloak_container_name}" "${var.keycloak_kcadm_path}")
    ;;
  kubectl)
    if [ -z "${var.keycloak_namespace}" ] || [ -z "${var.keycloak_pod_selector}" ]; then
      echo "keycloak_namespace and keycloak_pod_selector are required when kcadm_exec_mode=kubectl" >&2
      exit 1
    fi
    POD="$(kubectl -n "${var.keycloak_namespace}" get pod -l "${var.keycloak_pod_selector}" -o jsonpath='{.items[0].metadata.name}')"
    KCADM_BASE=(kubectl -n "${var.keycloak_namespace}" exec "$POD" -- "${var.keycloak_kcadm_path}")
    ;;
  *)
    echo "Unsupported kcadm_exec_mode: ${var.kcadm_exec_mode}" >&2
    exit 1
    ;;
esac

"${KCADM_BASE[@]}" config credentials \
  --server "${var.keycloak_url}" \
  --realm "${var.keycloak_auth_realm}" \
  --client "${var.keycloak_client_id}" \
  --secret "${var.keycloak_client_secret}"

"${KCADM_BASE[@]}" update "client-scopes/${self.triggers.scope_id}" -r "${var.realm_id}" \
  -s 'attributes.tc.required=${self.triggers.tc_required}' \
  -s 'attributes.tc.version=${self.triggers.tc_version}' \
  ${self.triggers.tc_url:+-s 'attributes.tc.url=${self.triggers.tc_url}'} \
  ${self.triggers.tc_template:+-s 'attributes.tc.template=${self.triggers.tc_template}'} \
  ${self.triggers.tc_key:+-s 'attributes.tc.key=${self.triggers.tc_key}'}
EOT
  }

  depends_on = [keycloak_openid_client_scope.scopes]
}
