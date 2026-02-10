package com.example.keycloak.terms;

import com.example.keycloak.terms.TermsModels.Term;
import org.keycloak.models.ClientModel;
import org.keycloak.models.UserModel;

import java.time.Instant;
import java.util.Objects;

public class TermsAcceptanceStore {

  // key format: tc.accepted.<clientId>.<termKey>
  public boolean isAccepted(UserModel user, ClientModel client, Term term) {
    String currentVersion = term.version();
    if (currentVersion == null || currentVersion.isBlank()) return false;

    String raw = user.getFirstAttribute(key(client, term));
    if (raw == null || raw.isBlank()) return false;

    // raw can be "version" (legacy) or "version|timestamp" (new)
    String storedVersion = raw;
    int sep = raw.indexOf('|');
    if (sep >= 0) {
      storedVersion = raw.substring(0, sep);
    }

    return Objects.equals(currentVersion, storedVersion);
  }

  public void markAccepted(UserModel user, ClientModel client, Term term) {
    String v = term.version();
    if (v == null || v.isBlank()) {
      throw new IllegalStateException("term.version is empty for key=" + term.key());
    }
    String value = v + "|" + Instant.now().toString();
    user.setSingleAttribute(key(client, term), value);

    // optional convenience: per-client last accepted time
    user.setSingleAttribute("tc.accepted." + client.getClientId() + ".__lastAcceptedAt", Instant.now().toString());
  }

  private String key(ClientModel client, Term term) {
    return "tc.accepted." + client.getClientId() + "." + term.key();
  }
}
