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
import java.util.List;
import java.util.Map;
import java.util.Objects;
import java.util.Set;
import java.util.concurrent.ExecutorService;
import java.util.concurrent.Executors;
import java.util.concurrent.Future;

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

    int first = 0;
    int max = cfg.batchSize;

    while (true) {
      final int pageFirst = first;

      boolean hasMore = KeycloakModelUtils.runJobInTransaction(factory, (KeycloakSession session) -> {
        RealmModel realm = session.realms().getRealm(realmId);
        if (realm == null) {
          Log.warn("realm not found: " + realmId);
          return false;
        }

        // ✅ 전체 유저 페이징 조회(호환성 높음)
        List<UserModel> users = session.users()
            .searchForUserStream(realm, Collections.emptyMap(), pageFirst, max)
            .toList();

        if (users.isEmpty()) {
          return false;
        }

        ExecutorService pool = Executors.newFixedThreadPool(cfg.maxConcurrency);
        try {
          List<Future<LookupResult>> futures = new ArrayList<>(users.size());

          for (UserModel u : users) {
            // Knox API의 query user_id=<username> 조건을 그대로 사용
            final String userId = u.getUsername();

            futures.add(pool.submit(() -> {
              try {
                String rawJson = knox.fetchRawJsonByUserId(
                    userId,
                    cfg.retryMaxAttempts,
                    cfg.retryBaseBackoffMs
                );
                return LookupResult.ok(userId, rawJson);
              } catch (Exception e) {
                return LookupResult.fail(userId, e);
              }
            }));
          }

          int nowEpoch = (int) (System.currentTimeMillis() / 1000L);
          int changedUsers = 0;
          int failedUsers = 0;
          int invalidatedUsers = 0;

          for (int i = 0; i < users.size(); i++) {
            UserModel user = users.get(i);

            LookupResult r;
            try {
              r = futures.get(i).get();
            } catch (Exception e) {
              failedUsers++;
              continue;
            }

            if (!r.success) {
              failedUsers++;
              continue;
            }

            JsonNode root;
            try {
              root = OM.readTree(r.rawJson);
            } catch (Exception e) {
              failedUsers++;
              continue;
            }

            Set<String> updatedKeys = new HashSet<>();
            boolean shouldInvalidate = false;

            for (Map.Entry<String, String> entry : cfg.mapping.entrySet()) {
              String attrKey = entry.getKey();

              // ✅ 새 키 생성 금지: 기존 key 없으면 스킵
              if (!user.getAttributes().containsKey(attrKey)) {
                continue;
              }

              String newValue = extractString(root, entry.getValue());
              if (newValue == null) {
                continue;
              }

              String currentValue = user.getFirstAttribute(attrKey);
              if (Objects.equals(currentValue, newValue)) {
                continue;
              }

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
              // ✅ 유저 단위 notBefore 설정 (의도 명확, 호환성 높음)
              session.users().setNotBeforeForUser(realm, user, nowEpoch);

              // ✅ 즉시 로그아웃: 유저 세션 제거
              session.sessions().removeUserSessions(realm, user);

              invalidatedUsers++;
            }
          }

          Log.info("realm=" + realm.getName()
              + " pageFirst=" + pageFirst
              + " pageSize=" + users.size()
              + " changedUsers=" + changedUsers
              + " invalidatedUsers=" + invalidatedUsers
              + " failedUsers=" + failedUsers);

        } finally {
          pool.shutdownNow();
        }

        return true;
      });

      if (!hasMore) {
        break;
      }
      first += max;
    }
  }

  private static final class LookupResult {
    final boolean success;
    final String userId;
    final String rawJson;
    final Exception error;

    private LookupResult(boolean success, String userId, String rawJson, Exception error) {
      this.success = success;
      this.userId = userId;
      this.rawJson = rawJson;
      this.error = error;
    }

    static LookupResult ok(String userId, String rawJson) {
      return new LookupResult(true, userId, rawJson, null);
    }

    static LookupResult fail(String userId, Exception e) {
      return new LookupResult(false, userId, null, e);
    }
  }

  /**
   * Extract string value from a JsonNode using dot-path.
   *
   * Behavior:
   * - If an intermediate node is an array, uses the first element.
   * - Returns null for missing/blank values.
   */
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
        if (node.isEmpty()) {
          return null;
        }
        node = node.get(0);
      }

      node = node.path(part);
    }

    if (node == null || node instanceof MissingNode || node.isMissingNode() || node.isNull()) {
      return null;
    }

    if (node.isArray()) {
      if (node.isEmpty()) {
        return null;
      }
      node = node.get(0);
    }

    String value = node.asText(null);
    if (value == null || value.isBlank()) {
      return null;
    }
    return value;
  }
}
