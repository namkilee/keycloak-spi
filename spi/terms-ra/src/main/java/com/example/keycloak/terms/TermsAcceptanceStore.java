package com.example.keycloak.terms;

import com.example.keycloak.terms.TermsModels.Term;
import org.keycloak.models.ClientModel;
import org.keycloak.models.UserModel;

public class TermsAcceptanceStore {

  // key format: tc.accepted.<clientId>.<termKey>
  public boolean isAccepted(UserModel user, ClientModel client, Term term) {
    String acceptedVersion = user.getFirstAttribute(key(client, term));
    return term.version().equals(acceptedVersion);
  }

  public void markAccepted(UserModel user, ClientModel client, Term term) {
    user.setSingleAttribute(key(client, term), term.version());
  }

  private String key(ClientModel client, Term term) {
    return "tc.accepted." + client.getClientId() + "." + term.key();
  }
}
