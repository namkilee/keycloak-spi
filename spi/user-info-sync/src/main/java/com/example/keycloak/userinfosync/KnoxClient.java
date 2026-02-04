package com.example.keycloak.userinfosync;

import com.fasterxml.jackson.databind.ObjectMapper;

import java.io.IOException;
import java.net.URI;
import java.net.URLEncoder;
import java.net.http.HttpClient;
import java.net.http.HttpRequest;
import java.net.http.HttpResponse;
import java.net.http.HttpTimeoutException;
import java.nio.charset.StandardCharsets;
import java.time.Duration;
import java.util.Map;
import java.util.concurrent.ThreadLocalRandom;

public class KnoxClient {
  private static final ObjectMapper OM = new ObjectMapper();

  private final HttpClient http;
  private final String baseUrl;
  private final String systemId;
  private final String bearerToken;
  private final int timeoutMs;
  private final String resultType;

  public KnoxClient(UserInfoSyncRealmConfig cfg) {
    this.baseUrl = requireEnv("KNOX_API_URL");
    this.systemId = requireEnv("KNOX_SYSTEM_ID");
    this.bearerToken = requireEnv("KNOX_API_TOKEN");
    this.timeoutMs = Math.max(500, cfg.httpTimeoutMs);
    this.resultType = cfg.resultType;

    this.http = HttpClient.newBuilder()
        .connectTimeout(Duration.ofMillis(this.timeoutMs))
        .build();
  }

  public String fetchRawJsonByUserId(String userId, int maxAttempts, int baseBackoffMs) {
    int attempts = Math.max(1, maxAttempts);
    int backoff = Math.max(50, baseBackoffMs); // 0 방지 + 최소 backoff

    int attempt = 0;
    while (true) {
      attempt++;
      try {
        return doRequest(userId);
      } catch (NonRetryableKnoxException e) {
        // ✅ 절대 재시도하지 않음
        throw e;
      } catch (RetryableKnoxException e) {
        if (attempt >= attempts) {
          throw e;
        }
        sleepWithBackoffAndJitter(backoff, attempt);
      }
    }
  }

  private String doRequest(String userId) {
    URI uri = buildUri(userId);

    String bodyJson;
    try {
      bodyJson = OM.writeValueAsString(Map.of("resultType", resultType));
    } catch (Exception e) {
      // 이건 구성 문제에 가까워서 non-retry로 처리(혹은 RuntimeException)
      throw new NonRetryableKnoxException("failed to build request body", e);
    }

    HttpRequest req = HttpRequest.newBuilder()
        .uri(uri)
        .timeout(Duration.ofMillis(timeoutMs))
        .header("Content-Type", "application/json")
        .header("system-id", systemId)
        .header("authorization", "Bearer " + bearerToken)
        .POST(HttpRequest.BodyPublishers.ofString(bodyJson))
        .build();

    try {
      HttpResponse<String> resp = http.send(req, HttpResponse.BodyHandlers.ofString());
      int code = resp.statusCode();

      if (code == 200) {
        return resp.body();
      }

      // ✅ retryable
      if (code == 429 || (code >= 500 && code <= 599)) {
        throw new RetryableKnoxException("retryable status=" + code);
      }

      // ✅ non-retryable: 4xx (특히 400/401/403)
      throw new NonRetryableKnoxException(
          "non-retry status=" + code + " body=" + safeTrim(resp.body())
      );
    } catch (HttpTimeoutException e) {
      throw new RetryableKnoxException("timeout", e);
    } catch (InterruptedException e) {
      Thread.currentThread().interrupt();
      throw new RetryableKnoxException("interrupted", e);
    } catch (IOException e) {
      throw new RetryableKnoxException("I/O error", e);
    }
  }

  private URI buildUri(String userId) {
    // baseUrl에 기존 query가 있어도 안전하게 붙이기 위한 최소 방어
    String encoded = URLEncoder.encode(userId, StandardCharsets.UTF_8);
    String sep = baseUrl.contains("?") ? "&" : "?";
    return URI.create(baseUrl + sep + "user_id=" + encoded);
  }

  private static String requireEnv(String key) {
    String v = System.getenv(key);
    if (v == null || v.isBlank()) {
      throw new IllegalStateException("Missing env: " + key);
    }
    return v;
  }

  private static void sleepWithBackoffAndJitter(int baseBackoffMs, int attempt) {
    long exp = 1L << Math.min(attempt - 1, 5); // cap 2^5
    long baseSleep = (long) baseBackoffMs * exp;

    // ✅ jitter: 0.7x ~ 1.3x
    double jitter = ThreadLocalRandom.current().nextDouble(0.7, 1.3);
    long sleep = (long) Math.max(0, baseSleep * jitter);

    try {
      Thread.sleep(sleep);
    } catch (InterruptedException ignored) {
      Thread.currentThread().interrupt();
    }
  }

  private static String safeTrim(String s) {
    if (s == null) return "";
    return s.length() > 200 ? s.substring(0, 200) : s;
  }

  public static class RetryableKnoxException extends RuntimeException {
    public RetryableKnoxException(String m) { super(m); }
    public RetryableKnoxException(String m, Throwable t) { super(m, t); }
  }

  public static class NonRetryableKnoxException extends RuntimeException {
    public NonRetryableKnoxException(String m) { super(m); }
    public NonRetryableKnoxException(String m, Throwable t) { super(m, t); }
  }
}
