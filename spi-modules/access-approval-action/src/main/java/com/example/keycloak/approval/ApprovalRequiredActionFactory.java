package com.example.keycloak.approval;

import org.keycloak.Config;
import org.keycloak.authentication.RequiredActionFactory;
import org.keycloak.authentication.RequiredActionProvider;
import org.keycloak.models.KeycloakSession;
import org.keycloak.models.KeycloakSessionFactory;
import org.keycloak.provider.ProviderConfigProperty;

import java.util.List;

public class ApprovalRequiredActionFactory implements RequiredActionFactory {

  @Override
  public String getId() {
    return ApprovalConstants.RA_PROVIDER_ID;
  }

  @Override
  public String getDisplayText() {
    return "Client Approval Required";
  }

  @Override
  public RequiredActionProvider create(KeycloakSession session) {
    return new ApprovalRequiredActionProvider();
  }

  @Override
  public void init(Config.Scope config) {
  }

  @Override
  public void postInit(KeycloakSessionFactory factory) {
  }

  @Override
  public void close() {
  }

  @Override
  public String getHelpText() {
    return "Checks client-specific approval status, supports client auto-approve, and blocks login until approved.";
  }

  @Override
  public List<ProviderConfigProperty> getConfigMetadata() {
    return List.of();
  }

  @Override
  public boolean isOneTimeAction() {
    return false;
  }
}