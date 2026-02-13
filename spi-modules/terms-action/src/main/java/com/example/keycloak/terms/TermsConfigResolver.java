package com.example.keycloak.terms;

import com.example.keycloak.terms.TermsModels.Term;
import com.example.keycloak.terms.TermsModels.TermsBundle;
import org.keycloak.models.ClientModel;
import org.keycloak.models.ClientScopeModel;

import java.util.*;
import java.util.regex.Matcher;
import java.util.regex.Pattern;

/**
 * Resolve terms from attached client scopes using attributes produced by tc_sync:
 *
 *   tc.<termKey>.required = "true|false"
 *   tc.<termKey>.version  = "<string>"
 *   tc.<termKey>.title    = "<string>" (optional)
 *   tc.<termKey>.url      = "<string>" (optional)
 *   tc.<termKey>.template = "<string>" (optional; currently ignored unless model extended)
 *
 * Scope priority:
 *   scope attribute "tc_priority" (string int). Higher wins.
 *
 * Merge:
 *   - Higher priority overrides lower priority
 *   - Same priority duplicate termKey => FAIL (configuration error)
 */
public final class TermsConfigResolver {

  private static final String PREFIX_ROOT = "tc";
  private static final String ATTR_PRIORITY = "tc_priority";

  // tc.<termKey>.<field>
  private static final Pattern KEY_PATTERN =
      Pattern.compile("^" + Pattern.quote(PREFIX_ROOT) + "\\.([^.]+)\\.([^.]+)$");

  public TermsBundle resolve(ClientModel client) {
    // Collect attached scopes: default + optional
    List<ClientScopeModel> allScopes = new ArrayList<>();
    allScopes.addAll(client.getClientScopes(true).values());
    allScopes.addAll(client.getClientScopes(false).values());

    // Sort by priority desc, then name asc (deterministic)
    List<ScopeWithPriority> ordered = allScopes.stream()
        .map(s -> new ScopeWithPriority(s, parsePriority(s.getAttribute(ATTR_PRIORITY))))
        .sorted(Comparator
            .comparingInt(ScopeWithPriority::priority).reversed()
            .thenComparing(x -> safe(x.scope().getName())))
        .toList();

    // termKey -> TermWithPriority
    Map<String, TermWithPriority> merged = new LinkedHashMap<>();

    for (ScopeWithPriority sp : ordered) {
      ClientScopeModel scope = sp.scope();
      int prio = sp.priority();

      Map<String, String> attrs = safeAttrs(scope);
      if (attrs.isEmpty()) continue;

      // termKey -> fields for this scope
      Map<String, Map<String, String>> scopeTerms = new LinkedHashMap<>();

      for (var e : attrs.entrySet()) {
        String k = e.getKey();
        if (k == null) continue;

        Matcher m = KEY_PATTERN.matcher(k);
        if (!m.matches()) continue;

        String termKey = m.group(1);
        String field = m.group(2);
        if (termKey == null || termKey.isBlank()) continue;
        if (field == null || field.isBlank()) continue;

        scopeTerms.computeIfAbsent(termKey, __ -> new LinkedHashMap<>())
            .put(field, e.getValue() == null ? "" : e.getValue());
      }

      // Apply merge
      for (var entry : scopeTerms.entrySet()) {
        String termKey = entry.getKey();
        Map<String, String> f = entry.getValue();

        Term t = toTerm(termKey, f, client, scope);

        TermWithPriority existing = merged.get(termKey);
        if (existing == null) {
          merged.put(termKey, new TermWithPriority(t, prio));
          continue;
        }

        if (existing.priority == prio) {
          // same priority duplicate => ambiguous config => fail closed
          throw new IllegalStateException(
              "Duplicate termKey '" + termKey + "' at same tc_priority=" + prio +
                  " for client '" + client.getClientId() + "'. " +
                  "Conflicting scope: '" + safe(scope.getName()) + "'."
          );
        }

        // higher prio wins (we iterate from high to low, so normally we won't reach here),
        // but keep it correct in case ordering changes.
        if (prio > existing.priority) {
          merged.put(termKey, new TermWithPriority(t, prio));
        }
      }
    }

    // Return ordered by required desc then key asc (stable UI)
    List<Term> terms = merged.values().stream()
        .map(tp -> tp.term)
        .sorted(
            Comparator.comparing(Term::required, Comparator.reverseOrder())
                .thenComparing(Term::key, Comparator.nullsLast(String::compareTo))
        )
        .toList();


    return new TermsBundle(List.copyOf(terms));
  }

  private static Term toTerm(String termKey, Map<String, String> f, ClientModel client, ClientScopeModel scope) {
    String version = trimToEmpty(f.get("version"));
    if (version.isBlank()) {
      throw new IllegalStateException(
          "Invalid term (missing version) for key='" + termKey + "' " +
              "in scope '" + safe(scope.getName()) + "' for client '" + client.getClientId() + "'."
      );
    }

    boolean required = "true".equalsIgnoreCase(trimToEmpty(f.get("required")));
    String title = trimToEmpty(f.get("title"));
    if (title.isBlank()) title = termKey;

    String url = trimToEmpty(f.get("url"));
    // template은 TermsModels.Term에 필드가 없어서 현재는 무시
    return new Term(termKey, title, version, url, required);
  }

  private static Map<String, String> safeAttrs(ClientScopeModel scope) {
    try {
      Map<String, String> attrs = scope.getAttributes();
      return attrs == null ? Map.of() : attrs;
    } catch (Exception e) {
      return Map.of();
    }
  }

  private static int parsePriority(String raw) {
    if (raw == null || raw.isBlank()) return 0;
    try { return Integer.parseInt(raw.trim()); }
    catch (Exception e) { return 0; } // fail-safe: treat invalid as lowest
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
    TermWithPriority(Term term, int priority) { this.term = term; this.priority = priority; }
  }
}
