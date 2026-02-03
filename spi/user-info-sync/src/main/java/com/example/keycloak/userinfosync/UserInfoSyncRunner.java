package com.example.keycloak.userinfosync;

import org.keycloak.models.KeycloakSession;
import org.keycloak.models.KeycloakSessionFactory;
import org.keycloak.models.RealmModel;
import org.keycloak.models.UserModel;
import org.keycloak.models.utils.KeycloakModelUtils;

import java.util.ArrayList;
import java.util.List;
import java.util.Objects;
import java.util.concurrent.ExecutorService;
import java.util.concurrent.Executors;
import java.util.concurrent.Future;

public class UserInfoSyncRunner {
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
      int pageFirst = first;
      boolean hasMore = KeycloakModelUtils.runJobInTransaction(factory, (KeycloakSession session) -> {
        RealmModel realm = session.realms().getRealm(realmId);
        if (realm == null) {
          Log.warn("realm not found: " + realmId);
          return false;
        }

        List<UserModel> users = session.users().getUsersStream(realm, pageFirst, max).toList();
        if (users.isEmpty()) {
          return false;
        }

        ExecutorService pool = Executors.newFixedThreadPool(cfg.maxConcurrency);
        try {
          List<Future<LookupResult>> futures = new ArrayList<>(users.size());
          for (UserModel u : users) {
            final String userId = u.getUsername();
            futures.add(pool.submit(() -> {
              try {
                KnoxUserInfo info = knox.fetchByUserId(
                    userId,
                    cfg.retryMaxAttempts,
                    cfg.retryBaseBackoffMs
                );
                return LookupResult.ok(userId, info);
              } catch (Exception e) {
                return LookupResult.fail(userId, e);
              }
            }));
          }

          int nowEpoch = (int) (System.currentTimeMillis() / 1000L);
          int changed = 0;
          int failed = 0;

          for (int i = 0; i < users.size(); i++) {
            UserModel user = users.get(i);
            LookupResult r;
            try {
              r = futures.get(i).get();
            } catch (Exception e) {
              failed++;
              continue;
            }

            if (!r.success) {
              failed++;
              continue;
            }

            String currentDeptId = user.getFirstAttribute(cfg.deptAttrKey);
            String newDeptId = r.info.departmentCode();

            if (Objects.equals(currentDeptId, newDeptId)) {
              continue;
            }

            user.setSingleAttribute(cfg.deptAttrKey, newDeptId);
            user.setNotBefore(nowEpoch);
            session.sessions().removeUserSessions(realm, user);

            changed++;
          }

          Log.info("realm=" + realm.getName()
              + " pageFirst=" + pageFirst
              + " pageSize=" + users.size()
              + " changed=" + changed
              + " failed=" + failed);

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
    final KnoxUserInfo info;
    final Exception error;

    private LookupResult(boolean success, String userId, KnoxUserInfo info, Exception error) {
      this.success = success;
      this.userId = userId;
      this.info = info;
      this.error = error;
    }

    static LookupResult ok(String userId, KnoxUserInfo info) {
      return new LookupResult(true, userId, info, null);
    }

    static LookupResult fail(String userId, Exception e) {
      return new LookupResult(false, userId, null, e);
    }
  }
}
