package com.example.keycloak.userinfosync;

import org.keycloak.cluster.ClusterProvider;
import org.keycloak.models.KeycloakSession;
import org.keycloak.models.KeycloakSessionFactory;
import org.keycloak.timer.ScheduledTask;

import java.time.ZoneId;
import java.time.ZonedDateTime;

public class UserInfoSyncScheduledTask implements ScheduledTask {
  private final KeycloakSessionFactory factory;

  public UserInfoSyncScheduledTask(KeycloakSessionFactory factory) {
    this.factory = factory;
  }

  @Override
  public void run(KeycloakSession session) {
    // 기본은 서버 timezone. realm별 timezone이 있으면 cfg에서 변환해서 쓰는 게 안전
    ZonedDateTime serverNow = ZonedDateTime.now();

    session.realms().getRealmsStream().forEach(realm -> {
      UserInfoSyncRealmConfig cfg = UserInfoSyncRealmConfig.fromRealm(realm);
      if (!cfg.enabled) return;

      // (권장) cfg에 timezone이 있다면 그 timezone 기준으로 window 판정
      ZonedDateTime now = serverNow;
      if (cfg.zoneId != null && !cfg.zoneId.isBlank()) { // cfg에 zoneId 추가 권장
        try {
          now = serverNow.withZoneSameInstant(ZoneId.of(cfg.zoneId));
        } catch (Exception ignored) {
          // 잘못된 zoneId면 서버 시간으로 fallback
        }
      }

      if (!cfg.isNowInWindow(now)) return;

      String dateKey = cfg.todayKey(now);
      String taskKey = cfg.buildTaskKey(realm.getId(), dateKey);

      ClusterProvider cluster = session.getProvider(ClusterProvider.class);
      int ttlSeconds = 26 * 60 * 60;

      Runnable job = () -> {
        Log.info("START realm=" + realm.getName() + " taskKey=" + taskKey);
        try {
          new UserInfoSyncRunner(factory, cfg).syncRealm(realm.getId());
          Log.info("DONE realm=" + realm.getName() + " taskKey=" + taskKey);
        } catch (Exception e) {
          Log.error("FAILED realm=" + realm.getName() + " taskKey=" + taskKey, e);
        }
      };

      // ✅ ClusterProvider가 없으면(단일노드/환경차이) 그냥 실행하도록 방어
      if (cluster == null) {
        Log.warn("ClusterProvider not available. Running locally. realm=" + realm.getName());
        job.run();
        return;
      }

      cluster.executeIfNotExecuted(taskKey, ttlSeconds, () -> {
        job.run();
        return null;
      });
    });
  }
}
