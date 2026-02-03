package com.example.keycloak.userinfosync;

import org.keycloak.models.RealmModel;

import java.time.Duration;
import java.time.ZoneId;
import java.time.ZonedDateTime;
import java.time.format.DateTimeFormatter;
import java.util.Map;

public final class UserInfoSyncRealmConfig {
  public final boolean enabled;
  public final String runAt;
  public final int windowMinutes;
  public final int batchSize;
  public final String deptAttrKey;
  public final String resultType;
  public final int httpTimeoutMs;
  public final int maxConcurrency;
  public final int retryMaxAttempts;
  public final int retryBaseBackoffMs;
  public final String taskKeyPrefix;
  public final ZoneId timezone;

  private UserInfoSyncRealmConfig(
      boolean enabled,
      String runAt,
      int windowMinutes,
      int batchSize,
      String deptAttrKey,
      String resultType,
      int httpTimeoutMs,
      int maxConcurrency,
      int retryMaxAttempts,
      int retryBaseBackoffMs,
      String taskKeyPrefix,
      ZoneId timezone
  ) {
    this.enabled = enabled;
    this.runAt = runAt;
    this.windowMinutes = windowMinutes;
    this.batchSize = batchSize;
    this.deptAttrKey = deptAttrKey;
    this.resultType = resultType;
    this.httpTimeoutMs = httpTimeoutMs;
    this.maxConcurrency = maxConcurrency;
    this.retryMaxAttempts = retryMaxAttempts;
    this.retryBaseBackoffMs = retryBaseBackoffMs;
    this.taskKeyPrefix = taskKeyPrefix;
    this.timezone = timezone;
  }

  public static UserInfoSyncRealmConfig fromRealm(RealmModel realm) {
    Map<String, String> attrs = realm.getAttributes();

    boolean enabled = "true".equalsIgnoreCase(attrs.getOrDefault("userinfosync.enabled", "false"));
    String runAt = attrs.getOrDefault("userinfosync.runAt", "03:00");
    int window = parseInt(attrs.getOrDefault("userinfosync.windowMinutes", "3"), 3);
    int batch = parseInt(attrs.getOrDefault("userinfosync.batchSize", "500"), 500);
    String deptKey = attrs.getOrDefault("userinfosync.deptAttrKey", "deptId");
    String resultType = attrs.getOrDefault("userinfosync.resultType", "basic");
    int timeout = parseInt(attrs.getOrDefault("userinfosync.httpTimeoutMs", "5000"), 5000);
    int conc = parseInt(attrs.getOrDefault("userinfosync.maxConcurrency", "15"), 15);
    int retry = parseInt(attrs.getOrDefault("userinfosync.retry.maxAttempts", "3"), 3);
    int backoff = parseInt(attrs.getOrDefault("userinfosync.retry.baseBackoffMs", "250"), 250);
    String prefix = attrs.getOrDefault("userinfosync.taskKeyPrefix", "userinfosync");

    ZoneId tz = ZoneId.systemDefault();

    if (!"basic".equalsIgnoreCase(resultType) && !"optional".equalsIgnoreCase(resultType)) {
      resultType = "basic";
    }

    return new UserInfoSyncRealmConfig(
        enabled,
        runAt,
        window,
        batch,
        deptKey,
        resultType,
        timeout,
        conc,
        retry,
        backoff,
        prefix,
        tz
    );
  }

  public boolean isNowInWindow(ZonedDateTime now) {
    ZonedDateTime zoned = now.withZoneSameInstant(timezone);

    String[] parts = runAt.split(":");
    if (parts.length != 2) {
      return false;
    }

    int hh = parseInt(parts[0], -1);
    int mm = parseInt(parts[1], -1);
    if (hh < 0 || hh > 23 || mm < 0 || mm > 59) {
      return false;
    }

    ZonedDateTime target = zoned.withHour(hh).withMinute(mm).withSecond(0).withNano(0);
    long diffMin = Math.abs(Duration.between(zoned, target).toMinutes());
    return diffMin <= windowMinutes;
  }

  public String todayKey(ZonedDateTime now) {
    return now.withZoneSameInstant(timezone).format(DateTimeFormatter.BASIC_ISO_DATE);
  }

  public String buildTaskKey(String realmId, String yyyymmdd) {
    return taskKeyPrefix + ":" + realmId + ":" + yyyymmdd;
  }

  private static int parseInt(String v, int fallback) {
    try {
      return Integer.parseInt(v);
    } catch (Exception e) {
      return fallback;
    }
  }
}
