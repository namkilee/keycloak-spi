package com.example.keycloak.terms;

import com.example.keycloak.terms.TermsModels.Term;
import com.example.keycloak.terms.TermsModels.TermsBundle;
import com.fasterxml.jackson.databind.JavaType;
import com.fasterxml.jackson.databind.ObjectMapper;
import org.keycloak.models.ClientModel;
import org.keycloak.models.ClientScopeModel;

import java.util.*;

/**
 * Resolve terms from attached client scopes only.
 *
 * - Each terms scope must have attribute: tc.terms = JSON array of Term
 * - Merge rule:
 *   1) shared terms scopes first (name starts with "shared-terms-")
 *   2) client-specific terms scopes override shared (any non-shared terms scope)
 * - Duplicates in the same layer => FAIL (configuration error)
 */
public final class TermsConfigResolver {

  public static final String ATTR_TERMS = "tc.terms";
  private static final String SHARED_PREFIX = "shared-terms-";

  private final ObjectMapper om = new ObjectMapper();

  public TermsBundle resolve(ClientModel client) {
    // Collect attached scopes: default + optional
    List<ClientScopeModel> allScopes = new ArrayList<>();
    allScopes.addAll(client.getClientScopes(true).values());
    allScopes.addAll(client.getClientScopes(false).values());

    // Only scopes that define tc.terms
    List<ClientScopeModel> termsScopes = allScopes.stream()
        .filter(s -> {
          String raw = s.getAttribute(ATTR_TERMS);
          return raw != null && !raw.isBlank();
        })
        .toList();

    // Split into shared vs client-specific (by name prefix; priority not used)
    List<ClientScopeModel> shared = termsScopes.stream()
        .filter(this::isSharedTermsScope)
        .toList();

    List<ClientScopeModel> clientSpecific = termsScopes.stream()
        .filter(s -> !isSharedTermsScope(s))
        .toList();

    Map<String, Term> sharedMap = loadLayer(client, "shared", shared);
    Map<String, Term> clientMap = loadLayer(client, "client", clientSpecific);

    // Merge: client overrides shared
    Map<String, Term> merged = new LinkedHashMap<>(sharedMap);
    merged.putAll(clientMap);

    return new TermsBundle(List.copyOf(merged.values()));
  }

  private boolean isSharedTermsScope(ClientScopeModel scope) {
    String name = scope.getName();
    return name != null && name.startsWith(SHARED_PREFIX);
  }

  private Map<String, Term> loadLayer(ClientModel client, String layer, List<ClientScopeModel> scopes) {
    Map<String, Term> out = new LinkedHashMap<>();

    for (ClientScopeModel scope : scopes) {
      String raw = scope.getAttribute(ATTR_TERMS);
      List<Term> terms = parseTerms(raw, scope, client);

      for (Term t : terms) {
        if (t.key() == null || t.key().isBlank()) {
          throw new IllegalStateException(errPrefix(client, layer, scope) + "term.key is empty");
        }
        if (t.version() == null || t.version().isBlank()) {
          throw new IllegalStateException(errPrefix(client, layer, scope) + "term.version is empty for key=" + t.key());
        }

        Term prev = out.putIfAbsent(t.key(), normalize(t));
        if (prev != null) {
          // same layer duplicate => configuration error (fail closed)
          throw new IllegalStateException(
              "Duplicate termKey '" + t.key() + "' within " + layer + " terms scopes " +
                  "for client '" + client.getClientId() + "'. " +
                  "Conflicting scope: '" + scope.getName() + "'."
          );
        }
      }
    }
    return out;
  }

  private Term normalize(Term t) {
    String title = (t.title() == null || t.title().isBlank()) ? t.key() : t.title();
    String url = (t.url() == null) ? "" : t.url();
    return new Term(t.key(), title, t.version(), url, t.required());
  }

  private List<Term> parseTerms(String raw, ClientScopeModel scope, ClientModel client) {
    try {
      JavaType type = om.getTypeFactory().constructCollectionType(List.class, Term.class);
      List<Term> parsed = om.readValue(raw, type);
      return parsed == null ? List.of() : parsed;
    } catch (Exception e) {
      throw new IllegalStateException(
          "Invalid tc.terms JSON in scope '" + scope.getName() + "' " +
              "for client '" + client.getClientId() + "'.", e
      );
    }
  }

  private String errPrefix(ClientModel client, String layer, ClientScopeModel scope) {
    return "Invalid term in " + layer + " scope '" + scope.getName() +
        "' for client '" + client.getClientId() + "': ";
  }
}
