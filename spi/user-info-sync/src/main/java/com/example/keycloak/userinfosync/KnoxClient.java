package com.example.keycloak.userinfosync;

import java.net.URI;
import java.net.URLEncoder;
import java.net.http.HttpClient;
import java.net.http.HttpRequest;
import java.net.http.HttpResponse;
import java.nio.charset.StandardCharsets;
import java.time.Duration;

public class KnoxClient {
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
    this.timeoutMs = cfg.httpTimeoutMs;
    this.resultType = cfg.resultType;

    this.http = HttpClient.newBuilder()
        .connectTimeout(Duration.ofMillis(timeoutMs))
        .build();
  }

  public String fetchRawJsonByUserId(String userId, int maxAttempts, int baseBackoffMs) {
    int attempt = 0;
    while (true) {
      attempt++;
      try {
        return doRequest(userId);
      } catch (RetryableKnoxException e) {
        if (attempt >= maxAttempts) {
          throw e;
        }
        sleepWithBackoff(baseBackoffMs, attempt);
      }
    }
  }

  private String doRequest(String userId) {
    String url = baseUrl + "?user_id=" + URLEncoder.encode(userId, StandardCharsets.UTF_8);
    String bodyJson = "{\"resultType\":\"" + resultType + "\"}";

    HttpRequest req = HttpRequest.newBuilder()
        .uri(URI.create(url))
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

      if (code == 429 || (code >= 500 && code <= 599)) {
        throw new RetryableKnoxException("retryable status=" + code);
      }

      throw new NonRetryableKnoxException(
          "non-retry status=" + code + " body=" + safeTrim(resp.body())
      );

    } catch (NonRetryableKnoxException e) {
      // ✅ 필수 수정: non-retryable은 절대 retryable로 바꾸지 않는다
      throw e;

    } catch (Exception e) {
      // 네트워크/타임아웃/기타 I/O 성격은 retryable로 처리
      throw new RetryableKnoxException("I/O error", e);
    }
  }

  private static String requireEnv(String key) {
    String v = System.getenv(key);
    if (v == null || v.isBlank()) {
      throw new IllegalStateException("Missing env: " + key);
    }
    return v;
  }

  private static void sleepWithBackoff(int baseBackoffMs, int attempt) {
    long sleep = (long) baseBackoffMs * (1L << Math.min(attempt - 1, 5));
    try {
      Thread.sleep(sleep);
    } catch (InterruptedException ignored) {
      Thread.currentThread().interrupt();
    }
  }

  private static String safeTrim(String s) {
    if (s == null) {
      return "";
    }
    return s.length() > 200 ? s.substring(0, 200) : s;
  }

  public static class RetryableKnoxException extends RuntimeException {
    public RetryableKnoxException(String m) {
      super(m);
    }

    public RetryableKnoxException(String m, Throwable t) {
      super(m, t);
    }
  }

  public static class NonRetryableKnoxException extends RuntimeException {
    public NonRetryableKnoxException(String m) {
      super(m);
    }
  }
}
