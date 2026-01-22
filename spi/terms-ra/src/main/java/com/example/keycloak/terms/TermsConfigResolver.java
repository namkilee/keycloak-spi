package com.example.keycloak.terms;

import com.example.keycloak.terms.TermsModels.Term;
import com.example.keycloak.terms.TermsModels.TermsBundle;
import org.keycloak.models.ClientModel;
import org.keycloak.models.ClientScopeModel;

import java.util.*;

public final class TermsConfigResolver {

  public static final String ATTR_REQUIRED = "tc.required";
  public static final String ATTR_PREFIX = "tc.term.";

  public TermsBundle resolve(ClientModel client) {
    String requiredRaw = getAttr(client, ATTR_REQUIRED);
    if (requiredRaw == null || requiredRaw.trim().isEmpty()) {
      return new TermsBundle(List.of());
    }

    List<String> ids = Arrays.stream(requiredRaw.split(","))
        .map(String::trim)
        .filter(s -> !s.isEmpty())
        .toList();

    List<Term> terms = new ArrayList<>();
    for (String id : ids) {
      String title = getAttr(client, ATTR_PREFIX + id + ".title");
      String version = getAttr(client, ATTR_PREFIX + id + ".version");
      String url = getAttr(client, ATTR_PREFIX + id + ".url");
      String required = getAttr(client, ATTR_PREFIX + id + ".required");

      boolean isRequired = required == null || required.isBlank() || Boolean.parseBoolean(required);

      if (title == null || title.isBlank()) title = id;
      if (version == null || version.isBlank()) version = "unknown";

      terms.add(new Term(id, title, version, url, isRequired));
    }

    return new TermsBundle(List.copyOf(terms));
  }

  /**
   * Lookup priority:
   * 1) Client attributes
   * 2) Attached client scopes attributes (default then optional)
   */
  private String getAttr(ClientModel client, String key) {
    String v = client.getAttribute(key);
    if (v != null && !v.isBlank()) return v;

    List<ClientScopeModel> scopes = new ArrayList<>();
    scopes.addAll(client.getClientScopes(true).values());
    scopes.addAll(client.getClientScopes(false).values());

    for (ClientScopeModel scope : scopes) {
      String sv = scope.getAttribute(key);
      if (sv != null && !sv.isBlank()) return sv;
    }
    return null;
  }
}
