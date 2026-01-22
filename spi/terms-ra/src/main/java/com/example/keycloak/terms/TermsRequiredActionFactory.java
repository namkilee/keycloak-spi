package com.example.keycloak.terms;

import org.keycloak.Config;
import org.keycloak.authentication.RequiredActionFactory;
import org.keycloak.authentication.RequiredActionProvider;
import org.keycloak.models.KeycloakSession;
import org.keycloak.models.KeycloakSessionFactory;

public class TermsRequiredActionFactory implements RequiredActionFactory {

  public static final String PROVIDER_ID = "terms-required-action";

  @Override
  public String getId() {
    return PROVIDER_ID;
  }

  @Override
  public String getDisplayText() {
    return "Terms & Conditions (multi)";
  }

  @Override
  public RequiredActionProvider create(KeycloakSession session) {
    return new TermsRequiredActionProvider(
        new TermsConfigResolver(),
        new TermsAcceptanceStore()
    );
  }

  @Override public void init(Config.Scope config) {}
  @Override public void postInit(KeycloakSessionFactory factory) {}
  @Override public void close() {}
}
