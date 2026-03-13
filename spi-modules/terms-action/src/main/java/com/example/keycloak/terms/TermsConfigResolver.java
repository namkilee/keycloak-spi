package com.example.keycloak.terms;

import com.example.keycloak.terms.TermsModels.Term;
import com.example.keycloak.terms.TermsModels.TermsBundle;
import com.fasterxml.jackson.databind.ObjectMapper;
import org.jboss.logging.Logger;
import org.keycloak.models.ClientModel;
import org.keycloak.models.ClientScopeModel;

import java.util.ArrayList;
import java.util.Comparator;
import java.util.LinkedHashMap;
import java.util.List;
import java.util.Map;

public final class TermsConfigResolver {

  private static final Logger LOG = Logger.getLogger(TermsConfigResolver.class);
  private static final String ATTR_TERMS_CONFIG = "terms_config";
  private static final String ATTR_PRIORITY = "terms_priority";
  private static final ObjectMapper MAPPER = new ObjectMapper();

  public TermsBundle resolve(ClientModel client) {
    List<ClientScopeModel> allScopes = new ArrayList<>();
    allScopes.addAll(client.getClientScopes(true).values());
    allScopes.addAll(client.getClientScopes(false).values());

    List<ScopeWithPriority> ordered = allScopes.stream()
        .map(s -> new ScopeWithPriority(s, parsePriority(s.getAttribute(ATTR_PRIORITY))))
        .sorted(Comparator
            .comparingInt(ScopeWithPriority::priority).reversed()
            .thenComparing(x -> safe(x.scope().getName())))
        .toList();

    Map<String, TermWithPriority> merged = new LinkedHashMap<>();

    for (ScopeWithPriority sp : ordered) {
      ClientScopeModel scope = sp.scope();
      int prio = sp.priority();

      List<ScopeTermConfig> scopeTerms = parseTermsConfig(scope, client);
      if (scopeTerms.isEmpty()) continue;

      for (ScopeTermConfig cfg : scopeTerms) {
        Term t = toTerm(cfg, client, scope);
        String termKey = t.key();

        TermWithPriority existing = merged.get(termKey);
        if (existing == null) {
          merged.put(termKey, new TermWithPriority(t, prio));
          continue;
        }

        if (existing.priority == prio) {
          throw new IllegalStateException(
              "Duplicate termKey '" + termKey + "' at same terms_priority=" + prio +
                  " for client '" + client.getClientId() + "'. " +
                  "Conflicting scope: '" + safe(scope.getName()) + "'."
          );
        }

        if (prio > existing.priority) {
          merged.put(termKey, new TermWithPriority(t, prio));
        }
      }
    }

    List<Term> terms = merged.values().stream()
        .map(tp -> tp.term)
        .sorted(
            Comparator.comparing(Term::required, Comparator.reverseOrder())
                .thenComparing(Term::key, Comparator.nullsLast(String::compareTo))
        )
        .toList();

    return new TermsBundle(List.copyOf(terms));
  }

  private static List<ScopeTermConfig> parseTermsConfig(ClientScopeModel scope, ClientModel client) {
    String raw = trimToEmpty(scope.getAttribute(ATTR_TERMS_CONFIG));
    if (raw.isBlank()) return List.of();

    try {
      TermsConfigPayload payload = MAPPER.readValue(raw, TermsConfigPayload.class);
      if (payload == null || payload.terms == null) {
        return List.of();
      }
      return payload.terms;
    } catch (Exception e) {
      LOG.errorf(e, "Invalid terms_config JSON in scope '%s' for client '%s'", safe(scope.getName()), client.getClientId());
      throw new IllegalStateException(
          "Invalid terms_config JSON in scope '" + safe(scope.getName()) +
              "' for client '" + client.getClientId() + "': " + e.getMessage(),
          e
      );
    }
  }

  private static Term toTerm(ScopeTermConfig cfg, ClientModel client, ClientScopeModel scope) {
    String termKey = trimToEmpty(cfg.key);
    if (termKey.isBlank()) {
      throw new IllegalStateException(
          "Invalid term key in scope '" + safe(scope.getName()) +
              "' for client '" + client.getClientId() + "'."
      );
    }

    String version = trimToEmpty(cfg.version);
    if (version.isBlank()) {
      throw new IllegalStateException(
          "Invalid term (missing version) for key='" + termKey + "' " +
              "in scope '" + safe(scope.getName()) + "' for client '" + client.getClientId() + "'."
      );
    }

    boolean required = Boolean.TRUE.equals(cfg.required);
    String title = trimToEmpty(cfg.title);
    if (title.isBlank()) title = termKey;

    String url = trimToEmpty(cfg.url);

    return new Term(termKey, title, version, url, required);
  }

  private static int parsePriority(String raw) {
    if (raw == null || raw.isBlank()) return 0;
    try {
      return Integer.parseInt(raw.trim());
    } catch (Exception e) {
      return 0;
    }
  }

  private static String trimToEmpty(String s) {
    return s == null ? "" : s.trim();
  }

  private static String safe(String s) {
    return s == null ? "" : s;
  }

  private record ScopeWithPriority(ClientScopeModel scope, int priority) {}

  private static final class TermWithPriority {
    final Term term;
    final int priority;

    TermWithPriority(Term term, int priority) {
      this.term = term;
      this.priority = priority;
    }
  }

  public static final class TermsConfigPayload {
    public List<ScopeTermConfig> terms;
  }

  public static final class ScopeTermConfig {
    public String key;
    public String title;
    public Boolean required;
    public String version;
    public String url;
  }
}
