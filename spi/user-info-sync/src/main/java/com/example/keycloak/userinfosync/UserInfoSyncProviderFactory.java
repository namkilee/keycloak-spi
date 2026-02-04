package com.example.keycloak.userinfosync;

import org.keycloak.models.KeycloakSession;
import org.keycloak.models.KeycloakSessionFactory;
import org.keycloak.models.RealmModel;
import org.keycloak.models.UserModel;
import org.keycloak.models.utils.KeycloakModelUtils;

import com.fasterxml.jackson.databind.JsonNode;
import com.fasterxml.jackson.databind.ObjectMapper;
import com.fasterxml.jackson.databind.node.MissingNode;

import java.util.ArrayList;
import java.util.Collections;
import java.util.HashSet;
import java.util.LinkedHashMap;
import java.util.List;
import java.util.Map;
import java.util.Objects;
import java.util.Set;
import java.util.concurrent.*;

public class UserInfoSyncRunner {
  private static final ObjectMapper OM = new ObjectMapper();

  private final KeycloakSessionFactory factory;
  private final UserInfoSyncRealmConfig cfg;

  public UserInfoSyncRunner(KeycloakSessionFactory factory, UserInfoSyncRealmConfig cfg) {
    this.factory = factory;
    this.cfg = cfg;
  }

  public void syncRealm(String realmId) {
    KnoxClient knox = new KnoxClient(cfg);

    // pool 재사용 (Runner 생명주기)
    ExecutorService pool = Executors.newFixedThreadPool(cfg.maxConcurrency);

    try {
      int first = 0;
      int max = cfg.batchSize;

      while (true) {
        final int pageFirst = first;

        // 1) TX-1: user identifiers만 짧게 가져오기
        PageSnapshot page = loadPageSnapshot(realmId, pageFirst, max);
        if (!page.hasMore) {
          break;
        }

        // 2) TX 밖: Knox 병렬 호출 + timeout
        Map<String, LookupResult> lookupByUsername =
            fetchKnoxInParallel(pool, knox, page.usernames);

        // 3) TX-2: 결과를 반영 (user 다시 로드 후 업데이트)
        applyUpdatesInTransaction(realmId, pageFirst, page.userIdsByUsername, lookupByUsername);

        first += max;
      }
    } finally {
      shutdownPool(pool);
    }
  }

  /**
   * TX-1: page의 유저 식별자만 가져온다 (UserModel 오래 들고있지 않기)
   */
  private PageSnapshot loadPageSnapshot(String realmId, int pageFirst, int max) {
    final PageSnapshot snapshot = new PageSnapshot();

    KeycloakModelUtils.runJobInTransaction(factory, (KeycloakSession session) -> {
      RealmModel realm = session.realms().getRealm(realmId);
      if (realm == null) {
        Log.warn("realm not found: " + realmId);
        snapshot.hasMore = false;
        return;
      }

      List<UserModel> users = session.users()
          .searchForUserStream(realm, Collections.emptyMap(), pageFirst, max)
          .toList();

      if (users.isEmpty()) {
        snapshot.hasMore = false;
        return;
      }

      // username -> userId (Keycloak 내부 UUID)
      // (LinkedHashMap: 검색 순서 유지)
      Map<String, String> map = new LinkedHashMap<>();
      for (UserModel u : users) {
        // Knox가 username 기반 조회라고 했으니 username 기준으로 snapshot 생성
        String username = u.getUsername();
        if (username == null || username.isBlank()) continue;
        map.put(username, u.getId());
      }

      snapshot.realmName = realm.getName();
      snapshot.userIdsByUsername = map;
      snapshot.usernames = new ArrayList<>(map.keySet());
      snapshot.hasMore = !snapshot.usernames.isEmpty();
    });

    return snapshot;
  }

  /**
   * TX 밖: Knox 병렬 호출. timeout/hang 방지.
   */
  private Map<String, LookupResult> fetchKnoxInParallel(
      ExecutorService pool,
      KnoxClient knox,
      List<String> usernames
  ) {
    Map<String, Future<LookupResult>> futures = new LinkedHashMap<>();
    for (String username : usernames) {
      futures.put(username, pool.submit(() -> {
        try {
          String rawJson = knox.fetchRawJsonByUserId(
              username,
              cfg.retryMaxAttempts,
              cfg.retryBaseBackoffMs
          );
          return LookupResult.ok(username, rawJson);
        } catch (Exception e) {
          return LookupResult.fail(username, e);
        }
      }));
    }

    // 결과 수집 (timeout 적용)
    Map<String, LookupResult> results = new LinkedHashMap<>();
    long perUserTimeoutMs = Math.max(1_000L, cfg.knoxPerUserTimeoutMs); // cfg에 추가 권장
    for (Map.Entry<String, Future<LookupResult>> entry : futures.entrySet()) {
      String username = entry.getKey();
      Future<LookupResult> f = entry.getValue();

      try {
        LookupResult r = f.get(perUserTimeoutMs, TimeUnit.MILLISECONDS);
        results.put(username, r);
      } catch (TimeoutException te) {
        f.cancel(true);
        results.put(username, LookupResult.fail(username, te));
      } catch (Exception e) {
        results.put(username, LookupResult.fail(username, e));
      }
    }

    return results;
  }

  /**
   * TX-2: user 재로딩 후 업데이트/무효화.
   */
  private void applyUpdatesInTransaction(
      String realmId,
      int pageFirst,
      Map<String, String> userIdsByUsername,
      Map<String, LookupResult> lookupByUsername
  ) {
    KeycloakModelUtils.runJobInTransaction(factory, (KeycloakSession session) -> {
      RealmModel realm = session.realms().getRealm(realmId);
      if (realm == null) {
        Log.warn("realm not found: " + realmId);
        return;
      }

      int nowEpoch = (int) (System.currentTimeMillis() / 1000L);
      int changedUsers = 0;
      int invalidatedUsers = 0;
      int failedUsers = 0;

      for (Map.Entry<String, String> e : userIdsByUsername.entrySet()) {
        String username = e.getKey();
        String userId = e.getValue();

        LookupResult r = lookupByUsername.get(username);
        if (r == null || !r.success || r.rawJson == null) {
          failedUsers++;
          continue;
        }

        JsonNode root;
        try {
          root = OM.readTree(r.rawJson);
        } catch (Exception ex) {
          failedUsers++;
          continue;
        }

        // ✅ 업데이트 TX에서 user 다시 로드
        UserModel user = session.users().getUserById(realm, userId);
        if (user == null) {
          // 중간에 삭제/변경될 수 있음
          failedUsers++;
          continue;
        }

        Set<String> updatedKeys = new HashSet<>();
        boolean shouldInvalidate = false;

        for (Map.Entry<String, String> mapping : cfg.mapping.entrySet()) {
          String attrKey = mapping.getKey();

          // ✅ 새 키 생성 금지: 기존 attribute key가 없으면 skip
          if (!user.getAttributes().containsKey(attrKey)) {
            continue;
          }

          String newValue = extractString(root, mapping.getValue());
          if (newValue == null) continue;

          String currentValue = user.getFirstAttribute(attrKey);
          if (Objects.equals(currentValue, newValue)) continue;

          user.setSingleAttribute(attrKey, newValue);
          updatedKeys.add(attrKey);

          if (cfg.invalidateOnKeys.contains(attrKey)) {
            shouldInvalidate = true;
          }
        }

        if (updatedKeys.isEmpty()) {
          continue;
        }

        changedUsers++;

        if (shouldInvalidate) {
          // ✅ 유저 notBefore 설정
          session.users().setNotBeforeForUser(realm, user, nowEpoch);

          // ✅ 즉시 로그아웃 (부하 크면 옵션화 추천)
          session.sessions().removeUserSessions(realm, user);

          invalidatedUsers++;
        }
      }

      Log.info("realm=" + realm.getName()
          + " pageFirst=" + pageFirst
          + " pageSize=" + userIdsByUsername.size()
          + " changedUsers=" + changedUsers
          + " invalidatedUsers=" + invalidatedUsers
          + " failedUsers=" + failedUsers);
    });
  }

  private void shutdownPool(ExecutorService pool) {
    pool.shutdown(); // 정상 종료 우선
    try {
      if (!pool.awaitTermination(10, TimeUnit.SECONDS)) {
        pool.shutdownNow(); // 그래도 안되면 강제
        if (!pool.awaitTermination(5, TimeUnit.SECONDS)) {
          Log.warn("executor did not terminate cleanly");
        }
      }
    } catch (InterruptedException ie) {
      pool.shutdownNow();
      Thread.currentThread().interrupt();
    }
  }

  private static final class PageSnapshot {
    boolean hasMore = true;
    String realmName;
    List<String> usernames = List.of();
    Map<String, String> userIdsByUsername = Map.of();
  }

  private static final class LookupResult {
    final boolean success;
    final String username;
    final String rawJson;
    final Exception error;

    private LookupResult(boolean success, String username, String rawJson, Exception error) {
      this.success = success;
      this.username = username;
      this.rawJson = rawJson;
      this.error = error;
    }

    static LookupResult ok(String username, String rawJson) {
      return new LookupResult(true, username, rawJson, null);
    }

    static LookupResult fail(String username, Exception e) {
      return new LookupResult(false, username, null, e);
    }
  }

  private static String extractString(JsonNode root, String dotPath) {
    if (root == null || dotPath == null || dotPath.isBlank()) {
      return null;
    }

    JsonNode node = root;
    for (String part : dotPath.split("\\.")) {
      if (node == null || node instanceof MissingNode || node.isMissingNode() || node.isNull()) {
        return null;
      }
      if (node.isArray()) {
        if (node.isEmpty()) return null;
        node = node.get(0);
      }
      node = node.path(part);
    }

    if (node == null || node instanceof MissingNode || node.isMissingNode() || node.isNull()) {
      return null;
    }
    if (node.isArray()) {
      if (node.isEmpty()) return null;
      node = node.get(0);
    }

    String value = node.asText(null);
    if (value == null || value.isBlank()) {
      return null;
    }
    return value;
  }
}
