package com.example.keycloak.approval;

import org.keycloak.Config;
import org.keycloak.authentication.RequiredActionFactory;
import org.keycloak.authentication.RequiredActionProvider;
import org.keycloak.models.KeycloakSession;
import org.keycloak.models.KeycloakSessionFactory;

public class ApprovalPendingRequiredActionFactory implements RequiredActionFactory {
  @Override public String getId() { return ApprovalConstants.RA_ID; }
  @Override public String getDisplayText() { return "Approval Pending"; }

  @Override
  public RequiredActionProvider create(KeycloakSession session) {
    return new ApprovalPendingRequiredAction();
  }

  @Override public void init(Config.Scope config) {}
  @Override public void postInit(KeycloakSessionFactory factory) {}
  @Override public void close() {}
}
