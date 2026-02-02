module "client_scopes" {
  source = "../scopes"

  realm_id = var.realm_id
  clients  = var.clients
  keycloak_url           = var.keycloak_url
  keycloak_auth_realm    = var.keycloak_auth_realm
  keycloak_client_id     = var.keycloak_client_id
  keycloak_client_secret = var.keycloak_client_secret
  kcadm_exec_mode        = var.kcadm_exec_mode
  keycloak_kcadm_path    = var.keycloak_kcadm_path
  keycloak_container_name = var.keycloak_container_name
  keycloak_namespace     = var.keycloak_namespace
  keycloak_pod_selector  = var.keycloak_pod_selector
}

resource "keycloak_required_action" "terms_required" {
  realm_id        = var.realm_id
  alias           = "terms-required-action"
  name            = "Terms & Conditions (multi)"
  enabled         = true
  default_action  = false
}

resource "keycloak_openid_client" "app" {
  for_each = var.clients

  realm_id                     = var.realm_id
  client_id                    = each.value.client_id
  name                         = each.value.name
  enabled                      = true
  access_type                  = each.value.access_type
  standard_flow_enabled        = each.value.standard_flow_enabled
  direct_access_grants_enabled = each.value.direct_access_grants_enabled
  pkce_code_challenge_method   = each.value.pkce_code_challenge_method
  root_url                     = each.value.root_url
  base_url                     = each.value.root_url
  valid_redirect_uris          = each.value.redirect_uris
  web_origins                  = each.value.web_origins
  login_theme                  = each.value.login_theme
}

resource "keycloak_openid_client_default_scopes" "app" {
  for_each = keycloak_openid_client.app

  realm_id  = var.realm_id
  client_id = each.value.id
  default_scopes = [
    for scope_key in var.clients[each.key].default_scopes :
    module.client_scopes.scope_names[each.key][scope_key]
  ]
  depends_on = [module.client_scopes]
}

resource "keycloak_saml_identity_provider" "saml_idp" {
  realm                      = var.realm_id
  alias                      = var.saml_idp_alias
  display_name               = var.saml_idp_display_name
  entity_id                  = var.saml_entity_id
  single_sign_on_service_url = var.saml_sso_url
  single_logout_service_url  = var.saml_slo_url
  signing_certificate        = var.saml_signing_certificate
  enabled                    = var.saml_enabled
  principal_type             = var.saml_principal_type
  principal_attribute        = var.saml_principal_attribute
  name_id_policy_format      = var.saml_name_id_policy_format
  validate_signature         = true
  post_binding_response      = true
  want_assertions_signed     = true
  extra_config = {
    idpEntityId = var.saml_idp_entity_id
  }
}

resource "keycloak_attribute_importer_identity_provider_mapper" "saml_idp" {
  for_each = {
    for mapper in var.saml_idp_mappers : mapper.name => mapper
    if mapper.type == "attribute_importer"
  }

  realm                   = var.realm_id
  name                    = each.value.name
  identity_provider_alias = keycloak_saml_identity_provider.saml_idp.alias
  attribute_name          = each.value.attribute_name
  attribute_friendly_name = each.value.attribute_friendly_name
  claim_name              = each.value.claim_name
  user_attribute          = each.value.user_attribute
  extra_config = merge(
    coalesce(each.value.extra_config, {}),
    { syncMode = each.value.sync_mode }
  )
}

resource "keycloak_hardcoded_attribute_identity_provider_mapper" "saml_idp" {
  for_each = {
    for mapper in var.saml_idp_mappers : mapper.name => mapper
    if mapper.type == "hardcoded_attribute"
  }

  realm                   = var.realm_id
  name                    = each.value.name
  identity_provider_alias = keycloak_saml_identity_provider.saml_idp.alias
  attribute_name          = each.value.attribute_name
  attribute_value         = each.value.attribute_value
  user_session            = each.value.user_session
  extra_config = merge(
    coalesce(each.value.extra_config, {}),
    { syncMode = each.value.sync_mode }
  )
}

resource "keycloak_attribute_to_role_identity_provider_mapper" "saml_idp" {
  for_each = {
    for mapper in var.saml_idp_mappers : mapper.name => mapper
    if mapper.type == "attribute_to_role"
  }

  realm                   = var.realm_id
  name                    = each.value.name
  identity_provider_alias = keycloak_saml_identity_provider.saml_idp.alias
  attribute_name          = each.value.attribute_name
  attribute_friendly_name = each.value.attribute_friendly_name
  attribute_value         = each.value.attribute_value
  claim_name              = each.value.claim_name
  claim_value             = each.value.claim_value
  role                    = each.value.role
  extra_config = merge(
    coalesce(each.value.extra_config, {}),
    { syncMode = each.value.sync_mode }
  )
}

resource "keycloak_custom_identity_provider_mapper" "saml_idp" {
  for_each = {
    for mapper in var.saml_idp_mappers : mapper.name => mapper
    if mapper.type == "custom"
  }

  realm                    = var.realm_id
  name                     = each.value.name
  identity_provider_alias  = keycloak_saml_identity_provider.saml_idp.alias
  identity_provider_mapper = each.value.identity_provider_mapper
  extra_config             = merge(
    coalesce(each.value.extra_config, {}),
    { syncMode = each.value.sync_mode }
  )
}

resource "keycloak_hardcoded_group_identity_provider_mapper" "saml_idp" {
  for_each = {
    for mapper in var.saml_idp_mappers : mapper.name => mapper
    if mapper.type == "hardcoded_group"
  }

  realm                   = var.realm_id
  name                    = each.value.name
  identity_provider_alias = keycloak_saml_identity_provider.saml_idp.alias
  group                   = each.value.group
  extra_config = merge(
    coalesce(each.value.extra_config, {}),
    { syncMode = each.value.sync_mode }
  )
}

resource "keycloak_hardcoded_role_identity_provider_mapper" "saml_idp" {
  for_each = {
    for mapper in var.saml_idp_mappers : mapper.name => mapper
    if mapper.type == "hardcoded_role"
  }

  realm                   = var.realm_id
  name                    = each.value.name
  identity_provider_alias = keycloak_saml_identity_provider.saml_idp.alias
  role                    = each.value.role
  extra_config = merge(
    coalesce(each.value.extra_config, {}),
    { syncMode = each.value.sync_mode }
  )
}

locals {
  user_profile = jsondecode(file("${path.module}/json/user-profile.json"))
}

resource "keycloak_realm_user_profile" "userprofile" {
  realm_id = var.realm_id

  dynamic "attribute" {
    for_each = try(local.user_profile.attributes, [])
    content {
      name = attribute.value.name
      display_name = try(attribute.value.displayName, null)
      multi_valued = attribute.value.multi_valued
      required_for_roles = try(attribute.value.required.roles, [])
      required_for_scopes = try(attribute.value.required.scopes, [])
      annotations = {
        for k, v in try(attribute.value.annotations, {}) :
        k => (can(tostring(v)) ? tostring(v) : jsonencode(v))
      }

      dynamic "permissions" {
        for_each = try([attribute.value.permissions], [])
        content {
          veiw = try(permissions.value.view, [])
          edit = try(permissions.value.edit, [])
        }
      }

      dynamic "validator" {
        for_each = try(attribute.value.validations, [])
        content {
          name = validator.key
          config = try(validator.value, {})
        }
      }
    }
  }

  dynamic "group" {
    for_each = try(local.user_profile.groups, [])
    content {
      name = group.value.name
      display_header = group.value.displayDescription
      annotations = {
        for k, v in try(group.value.annotations, {}) :
        k => (can(tostring(v)) ? tostring(v) : jsonencode(v))
      }
    }
  }
}

