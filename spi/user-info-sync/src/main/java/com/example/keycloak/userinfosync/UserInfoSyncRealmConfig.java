package com.example.keycloak.userinfosync;

import org.keycloak.models.RealmModel;

import com.fasterxml.jackson.databind.ObjectMapper;

import java.time.Duration;
import java.time.ZoneId;
import java.time.ZonedDateTime;
import java.time.format.DateTimeFormatter;
import java.util.Collections;
import java.util.Map;
import java.util.Set;
import java.util.stream.Collectors;

public final class UserInfoSyncRealmConfig {
  private static final ObjectMapper OM = new ObjectMapper();

  // 기본 매핑
  private static final String DEFAULT_MAPPING_JSON =
      "{\"deptId\":\"response.employees.departmentCode\"}";

  // ---- Realm attribute keys ----
  private static final String K_ENABLED = "userinfosync.enabled";
  private static final String K_RUN_AT = "userinfosync.runAt"; // HH:mm
  private static final String K_WINDOW_MIN = "userinfosync.windowMinutes";
  private static final String K_BATCH_SIZE = "userinfosync.batchSize";
  private static final String K_RESULT_TYPE = "userinfosync.resultType";
  private static final String K_HTTP_TIMEOUT_MS = "userinfosync.httpTimeoutMs";
  private static final String K_MAX_CONCURRENCY = "userinfosync.maxConcurrency";
  private static final String K_RETRY_MAX = "userinfosync.retry.maxAttempts";
  private static final String K_RETRY_BACKOFF = "userinfosync.retry.baseBackoffMs";
  private static final String K_TASK_PREFIX = "userinfosync.taskKeyPrefix";
  private static final String K_TIMEZONE = "userinfosync.timezone"; // e.g., Asia/Seoul, UTC
  private static final String K_MAPPING_JSON = "userinfosync.mappingJson";
  private static final String K_INVALIDATE_KEYS = "userinfosync.invalidateOnKeys";

  // (추가) Runner 운영 안정성 옵션
  private static final String K_KNOX_PER_USER_TIMEOUT_MS = "userinfosync.knoxPerUserTimeoutMs";
  private static final String K_INVALIDATE_LOGOUT = "userinfosync.invalidate.logout"; // true/false

  // ---- config fields ----
  public final boolean enabled;
  public final String runAt;          // HH:mm (validated)
  public final int windowMinutes;     // >=0
  public final int batchSize;         // bounded
  public final String resultType;     // basic|optional (currently informational)
  public final int httpTimeoutMs;     // bounded
  public final int maxConcurrency;    // bounded
  public final int retryMaxAttempts;  // bounded
  public final int retryBaseBackoffMs;// bounded
  public final String taskKeyPrefix;
  public final ZoneId timezone;
  public final Map<String, String> mapping;
  public final Set<String> invalidateOnKeys;

  // new
  public final long knoxPerUserTimeoutMs; // Future.get timeout
  public final boolean invalidateLogout;  // removeUserSessions 여부

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
      Set<String> invalidateOnKeys,
      long knoxPerUserTimeoutMs,
      boolean invalidateLogout
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
    this.knoxPerUserTimeoutMs = knoxPerUserTimeoutMs;
    this.invalidateLogout = invalidateLogout;
  }

  public static UserInfoSyncRealmConfig fromRealm(RealmModel realm) {
    Map<String, String> attrs = realm.getAttributes();

    boolean enabled = "true".equalsIgnoreCase(attrs.getOrDefault(K_ENABLED, "false"));

    String runAtRaw = attrs.getOrDefault(K_RUN_AT, "03:00");
    String runAt = normalizeRunAtOrDefault(runAtRaw, "03:00");

    int window = clamp(parseInt(attrs.getOrDefault(K_WINDOW_MIN, "3"), 3), 0, 120);
    int batch = clamp(parseInt(attrs.getOrDefault(K_BATCH_SIZE, "500"), 500), 1, 5000);

    String resultTypeRaw = attrs.getOrDefault(K_RESULT_TYPE, "basic");
    String resultType = ("optional".equalsIgnoreCase(resultTypeRaw) ? "optional" : "basic");

    int timeout = clamp(parseInt(attrs.getOrDefault(K_HTTP_TIMEOUT_MS, "5000"), 5000), 500, 60_000);
    int conc = clamp(parseInt(attrs.getOrDefault(K_MAX_CONCURRENCY, "15"), 15), 1, 200);

    int retry = clamp(parseInt(attrs.getOrDefault(K_RETRY_MAX, "3"), 3), 0, 10);
    int backoff = clamp(parseInt(attrs.getOrDefault(K_RETRY_BACKOFF, "250"), 250), 0, 10_000);

    String prefix = nonBlankOrDefault(attrs.getOrDefault(K_TASK_PREFIX, "userinfosync"), "userinfosync");

    ZoneId tz = parseZoneIdOrDefault(attrs.getOrDefault(K_TIMEZONE, null), ZoneId.systemDefault());

    String mappingJson = attrs.getOrDefault(K_MAPPING_JSON, DEFAULT_MAPPING_JSON);
    Map<String, String> mapping = parseMappingJsonOrFallback(mappingJson, DEFAULT_MAPPING_JSON);

    String invalidateCsv = attrs.getOrDefault(K_INVALIDATE_KEYS, "deptId");
    Set<String> invalidateOnKeys = parseCsv(invalidateCsv);

    long knoxPerUserTimeoutMs =
        clampLong(parseLong(attrs.getOrDefault(K_KNOX_PER_USER_TIMEOUT_MS, "8000"), 8000L), 1000L, 120_000L);

    boolean invalidateLogout =
        "true".equalsIgnoreCase(attrs.getOrDefault(K_INVALIDATE_LOGOUT, "true"));

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
        mapping,
        invalidateOnKeys,
        knoxPerUserTimeoutMs,
        invalidateLogout
    );
  }

  /**
   * now가 runAt(해당 timezone 기준) 주변 windowMinutes 이내인지.
   * ✅ 자정 교차 케이스(23:59 vs 00:01)도 올바르게 처리.
   */
  public boolean isNowInWindow(ZonedDateTime now) {
    ZonedDateTime zonedNow = now.withZoneSameInstant(timezone);

    int[] hm = parseRunAtHM(runAt);
    if (hm == null) return false;

    ZonedDateTime targetToday = zonedNow.withHour(hm[0]).withMinute(hm[1]).withSecond(0).withNano(0);
    ZonedDateTime targetPrev = targetToday.minusDays(1);
    ZonedDateTime targetNext = targetToday.plusDays(1);

    long diffToday = Math.abs(Duration.between(zonedNow, targetToday).toMinutes());
    long diffPrev  = Math.abs(Duration.between(zonedNow, targetPrev).toMinutes());
    long diffNext  = Math.abs(Duration.between(zonedNow, targetNext).toMinutes());

    long diffMin = Math.min(diffToday, Math.min(diffPrev, diffNext));
    return diffMin <= windowMinutes;
  }

  public String todayKey(ZonedDateTime now) {
    return now.withZoneSameInstant(timezone).format(DateTimeFormatter.BASIC_ISO_DATE);
  }

  public String buildTaskKey(String realmId, String yyyymmdd) {
    return taskKeyPrefix + ":" + realmId + ":" + yyyymmdd;
  }

  // ---- helpers ----

  private static int parseInt(String v, int fallback) {
    try {
      return Integer.parseInt(v);
    } catch (Exception e) {
      return fallback;
    }
  }

  private static long parseLong(String v, long fallback) {
    try {
      return Long.parseLong(v);
    } catch (Exception e) {
      return fallback;
    }
  }

  private static int clamp(int v, int min, int max) {
    return Math.max(min, Math.min(max, v));
  }

  private static long clampLong(long v, long min, long max) {
    return Math.max(min, Math.min(max, v));
  }

  private static String nonBlankOrDefault(String v, String fallback) {
    return (v == null || v.isBlank()) ? fallback : v;
  }

  private static ZoneId parseZoneIdOrDefault(String zoneId, ZoneId fallback) {
    if (zoneId == null || zoneId.isBlank()) return fallback;
    try {
      return ZoneId.of(zoneId.trim());
    } catch (Exception e) {
      Log.warn("Invalid timezone '" + zoneId + "', fallback to " + fallback);
      return fallback;
    }
  }

  private static String normalizeRunAtOrDefault(String runAtRaw, String fallback) {
    int[] hm = parseRunAtHM(runAtRaw);
    if (hm == null) {
      Log.warn("Invalid runAt '" + runAtRaw + "', fallback to " + fallback);
      return fallback;
    }
    // 0 padding 정규화
    return String.format("%02d:%02d", hm[0], hm[1]);
  }

  private static int[] parseRunAtHM(String runAt) {
    if (runAt == null) return null;
    String[] parts = runAt.trim().split(":");
    if (parts.length != 2) return null;

    int hh = parseInt(parts[0], -1);
    int mm = parseInt(parts[1], -1);
    if (hh < 0 || hh > 23 || mm < 0 || mm > 59) return null;

    return new int[]{hh, mm};
  }

  /**
   * ✅ 운영형: mappingJson이 깨져도 전체 태스크를 죽이지 않고 fallback.
   * (원하면 strict 옵션 추가해서 예외로 바꿀 수 있음)
   */
  private static Map<String, String> parseMappingJsonOrFallback(String json, String fallbackJson) {
    Map<String, String> parsed = parseMappingJsonOrNull(json);
    if (parsed != null) return parsed;

    Log.warn("Invalid userinfosync.mappingJson. Using fallback mapping.");
    Map<String, String> fallback = parseMappingJsonOrNull(fallbackJson);
    return fallback != null ? fallback : Collections.emptyMap();
  }

  private static Map<String, String> parseMappingJsonOrNull(String json) {
    if (json == null || json.isBlank()) return null;
    try {
      Map<String, String> mapping = OM.readValue(json, OM.getTypeFactory()
          .constructMapType(Map.class, String.class, String.class));
      return (mapping == null) ? null : mapping;
    } catch (Exception e) {
      return null;
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
