package com.example.keycloak.userinfosync;

import org.keycloak.cluster.ClusterProvider;
import org.keycloak.models.KeycloakSession;
import org.keycloak.models.KeycloakSessionFactory;
import org.keycloak.timer.ScheduledTask;

import java.time.ZonedDateTime;

public class UserInfoSyncScheduledTask implements ScheduledTask {
  private final KeycloakSessionFactory factory;

  public UserInfoSyncScheduledTask(KeycloakSessionFactory factory) {
    this.factory = factory;
  }

  @Override
  public void run(KeycloakSession session) {
    ZonedDateTime now = ZonedDateTime.now();

    session.realms().getRealmsStream().forEach(realm -> {
      UserInfoSyncRealmConfig cfg = UserInfoSyncRealmConfig.fromRealm(realm);
      if (!cfg.enabled) {
        return;
      }

      if (!cfg.isNowInWindow(now)) {
        return;
      }

      String dateKey = cfg.todayKey(now);
      String taskKey = cfg.buildTaskKey(realm.getId(), dateKey);

      ClusterProvider cluster = session.getProvider(ClusterProvider.class);
      int ttlSeconds = 26 * 60 * 60;

      cluster.executeIfNotExecuted(taskKey, ttlSeconds, () -> {
        Log.info("START realm=" + realm.getName() + " taskKey=" + taskKey);

        try {
          new UserInfoSyncRunner(factory, cfg).syncRealm(realm.getId());
          Log.info("DONE realm=" + realm.getName() + " taskKey=" + taskKey);
        } catch (Exception e) {
          Log.error("FAILED realm=" + realm.getName() + " taskKey=" + taskKey, e);
        }
        return null;
      });
    });
  }
}
