package com.example.keycloak.userinfosync;

import org.keycloak.models.KeycloakSession;
import org.keycloak.models.KeycloakSessionFactory;
import org.keycloak.provider.Provider;
import org.keycloak.provider.ProviderFactory;
import org.keycloak.timer.TimerProvider;

public class UserInfoSyncProviderFactory implements ProviderFactory<Provider> {

  @Override
  public Provider create(KeycloakSession session) {
    return () -> {};
  }

  @Override
  public void init(org.keycloak.Config.Scope config) {
  }

  @Override
  public void postInit(KeycloakSessionFactory factory) {
    long tickMillis = 60_000L;

    try (KeycloakSession session = factory.create()) {
      TimerProvider timer = session.getProvider(TimerProvider.class);
      timer.scheduleTask(new UserInfoSyncScheduledTask(factory), tickMillis);
      Log.info("UserInfoSync scheduled with tickMillis=" + tickMillis);
    } catch (Exception e) {
      Log.error("Failed to schedule UserInfoSync task", e);
    }
  }

  @Override
  public void close() {
  }

  @Override
  public String getId() {
    return "user-info-sync-provider";
  }
}
