package com.example.keycloak.terms;

import com.example.keycloak.terms.TermsModels.Term;
import com.example.keycloak.terms.TermsModels.TermsBundle;
import jakarta.ws.rs.core.MultivaluedMap;
import jakarta.ws.rs.core.Response;
import org.keycloak.authentication.RequiredActionContext;
import org.keycloak.authentication.RequiredActionProvider;
import org.keycloak.models.AuthenticationSessionModel;
import org.keycloak.models.ClientModel;
import org.keycloak.models.UserModel;

import java.util.List;
import java.util.Set;

public class TermsRequiredActionProvider implements RequiredActionProvider {

  private static final String FORM_PARAM_ACCEPTED = "accepted";

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

    boolean missing = requiredTerms.stream().anyMatch(t -> !store.isAccepted(user, client, t));
    if (missing) {
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
    Set<String> accepted = acceptedList == null ? Set.of() : Set.copyOf(acceptedList);

    List<Term> missing = requiredTerms.stream()
        .filter(t -> !accepted.contains(t.id()))
        .toList();

    if (!missing.isEmpty()) {
      Response challenge = context.form()
          .setError("You must accept all required terms.")
          .setAttribute("terms", bundle.terms())
          .setAttribute("missing", missing.stream().map(Term::id).toList())
          .createForm("terms.ftl");
      context.challenge(challenge);
      return;
    }

    for (Term t : requiredTerms) {
      store.markAccepted(user, client, t);
    }

    user.removeRequiredAction(TermsRequiredActionFactory.PROVIDER_ID);
    context.success();
  }

  @Override public void close() {}
}
