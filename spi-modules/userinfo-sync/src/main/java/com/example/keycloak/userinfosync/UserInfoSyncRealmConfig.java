package com.example.keycloak.userinfosync;

import org.keycloak.models.RealmModel;

import java.time.Duration;
import java.time.ZoneId;
import java.time.ZonedDateTime;
import java.time.format.DateTimeFormatter;
import java.util.Collections;
import java.util.Map;
import java.util.Set;
import java.util.stream.Collectors;

import com.fasterxml.jackson.databind.ObjectMapper;

public final class UserInfoSyncRealmConfig {
  private static final ObjectMapper OM = new ObjectMapper();
  private static final String DEFAULT_MAPPING_JSON =
      "{\"deptId\":\"response.employees.departmentCode\"}";

  public final boolean enabled;
  public final String runAt;
  public final int windowMinutes;
  public final int batchSize;
  public final String resultType;
  public final int httpTimeoutMs;
  public final int maxConcurrency;
  public final int retryMaxAttempts;
  public final int retryBaseBackoffMs;
  public final String taskKeyPrefix;
  public final ZoneId timezone;
  public final Map<String, String> mapping;
  public final Set<String> invalidateOnKeys;

  private UserInfoSyncRealmConfig(
      boolean enabled,
      String runAt,
      int windowMinutes,
      int batchSize,
      String resultType,
      int httpTimeoutMs,
      int maxConcurrency,
      int retryMaxAttempts,
      int retryBaseBackoffMs,
      String taskKeyPrefix,
      ZoneId timezone,
      Map<String, String> mapping,
      Set<String> invalidateOnKeys
  ) {
    this.enabled = enabled;
    this.runAt = runAt;
    this.windowMinutes = windowMinutes;
    this.batchSize = batchSize;
    this.resultType = resultType;
    this.httpTimeoutMs = httpTimeoutMs;
    this.maxConcurrency = maxConcurrency;
    this.retryMaxAttempts = retryMaxAttempts;
    this.retryBaseBackoffMs = retryBaseBackoffMs;
    this.taskKeyPrefix = taskKeyPrefix;
    this.timezone = timezone;
    this.mapping = mapping;
    this.invalidateOnKeys = invalidateOnKeys;
  }

  public static UserInfoSyncRealmConfig fromRealm(RealmModel realm) {
    Map<String, String> attrs = realm.getAttributes();

    boolean enabled = "true".equalsIgnoreCase(attrs.getOrDefault("userinfosync.enabled", "false"));
    String runAt = attrs.getOrDefault("userinfosync.runAt", "03:00");
    int window = parseInt(attrs.getOrDefault("userinfosync.windowMinutes", "3"), 3);
    int batch = parseInt(attrs.getOrDefault("userinfosync.batchSize", "500"), 500);
    String resultType = attrs.getOrDefault("userinfosync.resultType", "basic");
    int timeout = parseInt(attrs.getOrDefault("userinfosync.httpTimeoutMs", "5000"), 5000);
    int conc = parseInt(attrs.getOrDefault("userinfosync.maxConcurrency", "15"), 15);
    int retry = parseInt(attrs.getOrDefault("userinfosync.retry.maxAttempts", "3"), 3);
    int backoff = parseInt(attrs.getOrDefault("userinfosync.retry.baseBackoffMs", "250"), 250);
    String prefix = attrs.getOrDefault("userinfosync.taskKeyPrefix", "userinfosync");
    String mappingJson = attrs.getOrDefault("userinfosync.mappingJson", DEFAULT_MAPPING_JSON);
    String invalidateCsv = attrs.getOrDefault("userinfosync.invalidateOnKeys", "deptId");

    ZoneId tz = ZoneId.systemDefault();

    if (!"basic".equalsIgnoreCase(resultType) && !"optional".equalsIgnoreCase(resultType)) {
      resultType = "basic";
    }

    return new UserInfoSyncRealmConfig(
        enabled,
        runAt,
        window,
        batch,
        resultType,
        timeout,
        conc,
        retry,
        backoff,
        prefix,
        tz,
        parseMappingJson(mappingJson),
        parseCsv(invalidateCsv)
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

    // ✅ 필수 수정: 자정 교차 대응(어제/오늘/내일 중 최소 차이)
    ZonedDateTime targetToday = zoned.withHour(hh).withMinute(mm).withSecond(0).withNano(0);
    ZonedDateTime targetPrev = targetToday.minusDays(1);
    ZonedDateTime targetNext = targetToday.plusDays(1);

    long diffToday = Math.abs(Duration.between(zoned, targetToday).toMinutes());
    long diffPrev  = Math.abs(Duration.between(zoned, targetPrev).toMinutes());
    long diffNext  = Math.abs(Duration.between(zoned, targetNext).toMinutes());

    long diffMin = Math.min(diffToday, Math.min(diffPrev, diffNext));
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

  private static Map<String, String> parseMappingJson(String json) {
    if (json == null || json.isBlank()) {
      return Collections.emptyMap();
    }
    try {
      Map<String, String> mapping = OM.readValue(json, OM.getTypeFactory()
          .constructMapType(Map.class, String.class, String.class));
      return mapping == null ? Collections.emptyMap() : mapping;
    } catch (Exception e) {
      throw new IllegalArgumentException("Invalid userinfosync.mappingJson", e);
    }
  }

  private static Set<String> parseCsv(String csv) {
    if (csv == null || csv.isBlank()) {
      return Collections.emptySet();
    }
    return java.util.Arrays.stream(csv.split(","))
        .map(String::trim)
        .filter(s -> !s.isEmpty())
        .collect(Collectors.toSet());
  }
}
