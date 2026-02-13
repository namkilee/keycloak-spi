package com.example.keycloak.approval;

import org.keycloak.authentication.*;
import org.keycloak.models.KeycloakSession;
import org.keycloak.models.KeycloakSessionFactory;

import java.util.List;

public class ApprovalGateAuthenticatorFactory implements AuthenticatorFactory {
  public static final String PROVIDER_ID = "approval-gate-authenticator";

  @Override public String getId() { return PROVIDER_ID; }
  @Override public String getDisplayType() { return "Approval Gate (auto_approve + approved role)"; }
  @Override public String getHelpText() { return "Adds required action for pending approvals, auto-grants approved role if auto_approve=true."; }
  @Override public Authenticator create(KeycloakSession session) { return new ApprovalGateAuthenticator(); }

  @Override public void init(org.keycloak.Config.Scope config) {}
  @Override public void postInit(KeycloakSessionFactory factory) {}
  @Override public void close() {}

  @Override public boolean isConfigurable() { return false; }
  @Override public Requirement[] getRequirementChoices() {
    return new Requirement[]{ Requirement.REQUIRED, Requirement.DISABLED };
  }
  @Override public List<ProviderConfigProperty> getConfigProperties() { return List.of(); }
  @Override public String getReferenceCategory() { return "approval"; }
}
