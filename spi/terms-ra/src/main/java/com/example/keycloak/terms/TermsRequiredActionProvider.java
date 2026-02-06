package com.example.keycloak.terms;

import com.example.keycloak.terms.TermsModels.Term;
import com.example.keycloak.terms.TermsModels.TermsBundle;
import jakarta.ws.rs.core.MultivaluedMap;
import jakarta.ws.rs.core.Response;
import org.keycloak.authentication.RequiredActionContext;
import org.keycloak.authentication.RequiredActionProvider;
import org.keycloak.sessions.AuthenticationSessionModel;
import org.keycloak.models.ClientModel;
import org.keycloak.models.UserModel;

import java.util.*;
import java.util.stream.Collectors;

public class TermsRequiredActionProvider implements RequiredActionProvider {

  private static final String FORM_PARAM_ACCEPTED = "accepted"; // checkbox name="accepted" value="<termKey>"

  private final TermsConfigResolver resolver;
  private final TermsAcceptanceStore store;

  public TermsRequiredActionProvider(TermsConfigResolver resolver, TermsAcceptanceStore store) {
    this.resolver = resolver;
    this.store = store;
  }

  @Override
  public void evaluateTriggers(RequiredActionContext context) {
    UserModel user = context.getUser();
    AuthenticationSessionModel authSession = context.getAuthenticationSession();
    ClientModel client = authSession.getClient();

    TermsBundle bundle = resolver.resolve(client);
    List<Term> requiredTerms = bundle.terms().stream().filter(Term::required).toList();

    boolean missingRequired = requiredTerms.stream().anyMatch(t -> !store.isAccepted(user, client, t));
    if (missingRequired) {
      user.addRequiredAction(TermsRequiredActionFactory.PROVIDER_ID);
    }
  }

  @Override
  public void requiredActionChallenge(RequiredActionContext context) {
    ClientModel client = context.getAuthenticationSession().getClient();
    TermsBundle bundle = resolver.resolve(client);

    Response challenge = context.form()
        .setAttribute("terms", bundle.terms())
        .createForm("terms.ftl");

    context.challenge(challenge);
  }

  @Override
  public void processAction(RequiredActionContext context) {
    UserModel user = context.getUser();
    ClientModel client = context.getAuthenticationSession().getClient();

    TermsBundle bundle = resolver.resolve(client);
    List<Term> requiredTerms = bundle.terms().stream().filter(Term::required).toList();

    MultivaluedMap<String, String> form = context.getHttpRequest().getDecodedFormParameters();
    List<String> acceptedList = form.get(FORM_PARAM_ACCEPTED);
    Set<String> accepted = acceptedList == null ? Set.of() : new HashSet<>(acceptedList);

    // 1) required must be checked
    List<Term> missingRequired = requiredTerms.stream()
        .filter(t -> !accepted.contains(t.key()))
        .toList();

    if (!missingRequired.isEmpty()) {
      Response challenge = context.form()
          .setError("You must accept all required terms.")
          .setAttribute("terms", bundle.terms())
          .setAttribute("missing", missingRequired.stream().map(Term::key).toList())
          .createForm("terms.ftl");
      context.challenge(challenge);
      return;
    }

    // 2) store accepted for ALL checked terms (required + optional)
    Map<String, Term> byKey = bundle.terms().stream()
        .collect(Collectors.toMap(Term::key, t -> t, (a, b) -> a, LinkedHashMap::new));

    for (String k : accepted) {
      Term t = byKey.get(k);
      if (t != null) {
        store.markAccepted(user, client, t);
      }
    }

    user.removeRequiredAction(TermsRequiredActionFactory.PROVIDER_ID);
    context.success();
  }

  @Override public void close() {}
}
