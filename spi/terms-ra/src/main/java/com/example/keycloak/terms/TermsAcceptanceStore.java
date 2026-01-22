package com.example.keycloak.terms;

import com.example.keycloak.terms.TermsModels.Term;
import org.keycloak.models.ClientModel;
import org.keycloak.models.UserModel;

import java.time.OffsetDateTime;

public class TermsAcceptanceStore {

  // key format: tc.accepted.<clientId>.<termId>.version
  public boolean isAccepted(UserModel user, ClientModel client, Term term) {
    String acceptedVersion = user.getFirstAttribute(key(client, term));
    return term.version().equals(acceptedVersion);
  }

  public void markAccepted(UserModel user, ClientModel client, Term term) {
    user.setSingleAttribute(key(client, term), term.version());
    user.setSingleAttribute(key(client, term) + ".at", OffsetDateTime.now().toString());
  }

  private String key(ClientModel client, Term term) {
    return "tc.accepted." + client.getClientId() + "." + term.id() + ".version";
  }
}
