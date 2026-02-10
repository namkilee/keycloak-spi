package com.example.keycloak.terms;

import com.example.keycloak.terms.TermsModels.Term;
import com.example.keycloak.terms.TermsModels.TermsBundle;
import jakarta.ws.rs.core.MultivaluedMap;
import jakarta.ws.rs.core.Response;
import org.jboss.logging.Logger;
import org.keycloak.authentication.AuthenticationFlowError;
import org.keycloak.authentication.RequiredActionContext;
import org.keycloak.authentication.RequiredActionProvider;
import org.keycloak.models.ClientModel;
import org.keycloak.models.UserModel;
import org.keycloak.sessions.AuthenticationSessionModel;

import java.util.*;
import java.util.stream.Collectors;

public class TermsRequiredActionProvider implements RequiredActionProvider {

  private static final Logger LOG = Logger.getLogger(TermsRequiredActionProvider.class);

  private static final String FORM_PARAM_ACCEPTED = "accepted"; // checkbox name="accepted"
  private static final String FORM_PARAM_ACTION = "action";     // button name="action"
  private static final String ACTION_ACCEPT = "accept";
  private static final String ACTION_REJECT = "reject";

  // i18n keys (themes/*/login/messages*.properties에 추가)
  private static final String ERR_REQUIRED_MISSING = "terms.error.requiredMissing";
  private static final String ERR_REJECTED = "terms.error.rejected";
  private static final String ERR_NO_TERMS = "terms.error.noTerms";

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
    List<Term> terms = (bundle == null || bundle.terms() == null) ? List.of() : bundle.terms();
    List<Term> requiredTerms = terms.stream().filter(Term::required).toList();

    boolean missingRequired = requiredTerms.stream().anyMatch(t -> !store.isAccepted(user, client, t));

    LOG.debugf("TERMS evaluateTriggers client=%s user=%s missingRequired=%s",
        client.getClientId(), safeUser(user), missingRequired);

    if (missingRequired) {
      user.addRequiredAction(TermsRequiredActionFactory.PROVIDER_ID);
    }
  }

  @Override
  public void requiredActionChallenge(RequiredActionContext context) {
    ClientModel client = context.getAuthenticationSession().getClient();
    TermsBundle bundle = resolver.resolve(client);

    List<Term> terms = (bundle == null || bundle.terms() == null) ? List.of() : bundle.terms();

    Response challenge = context.form()
        .setAttribute("terms", terms)
        .setAttribute("missing", List.of())
        .createForm("terms.ftl");

    context.challenge(challenge);
  }

  @Override
  public void processAction(RequiredActionContext context) {
    UserModel user = context.getUser();
    ClientModel client = context.getAuthenticationSession().getClient();

    TermsBundle bundle = resolver.resolve(client);
    List<Term> terms = (bundle == null || bundle.terms() == null) ? List.of() : bundle.terms();
    List<Term> requiredTerms = terms.stream().filter(Term::required).toList();

    if (terms.isEmpty()) {
      Response challenge = context.form()
          .setAttribute("terms", List.of())
          .setAttribute("missing", List.of())
          .setAttribute("errorKey", ERR_NO_TERMS)
          .createForm("terms.ftl");
      context.challenge(challenge);
      return;
    }

    MultivaluedMap<String, String> form = context.getHttpRequest().getDecodedFormParameters();

    String action = firstOrDefault(form.get(FORM_PARAM_ACTION), ACTION_ACCEPT);

    // Reject: 정책상 로그인 중단이 맞으면 failureChallenge를 써도 됨.
    // 여기서는 "같은 페이지에 에러 표시 + 더 진행 못하게"를 택함.
    if (ACTION_REJECT.equals(action)) {
      Response challenge = context.form()
          .setAttribute("terms", terms)
          .setAttribute("missing", List.of())
          .setAttribute("errorKey", ERR_REJECTED)
          .createForm("terms.ftl");
      context.failureChallenge(AuthenticationFlowError.ACCESS_DENIED, challenge);
      return;
    }

    List<String> acceptedList = form.get(FORM_PARAM_ACCEPTED);
    Set<String> accepted = acceptedList == null ? Set.of() : new HashSet<>(acceptedList);

    // required must be checked
    List<String> missingRequiredKeys = requiredTerms.stream()
        .map(Term::key)
        .filter(k -> k != null && !k.isBlank())
        .filter(k -> !accepted.contains(k))
        .toList();

    if (!missingRequiredKeys.isEmpty()) {
      Response challenge = context.form()
          .setAttribute("terms", terms)
          .setAttribute("missing", missingRequiredKeys)   // required만 내려줌(FTL 로직과 일치)
          .setAttribute("errorKey", ERR_REQUIRED_MISSING) // i18n key
          .createForm("terms.ftl");
      context.challenge(challenge);
      return;
    }

    // store accepted for ALL checked terms (required + optional)
    Map<String, Term> byKey = terms.stream()
        .collect(Collectors.toMap(Term::key, t -> t, (a, b) -> a, LinkedHashMap::new));

    for (String k : accepted) {
      Term t = byKey.get(k);
      if (t != null) {
        store.markAccepted(user, client, t); // version|timestamp 저장
      }
    }

    // 디버깅용(문제 재발 시 원인 확정)
    LOG.debugf("TERMS processAction success client=%s user=%s accepted=%s",
        client.getClientId(), safeUser(user), accepted);

    // ✅ 매우 중요: user 뿐 아니라 authentication session에도 남아있을 수 있어 같이 제거
    user.removeRequiredAction(TermsRequiredActionFactory.PROVIDER_ID);
    context.getAuthenticationSession().removeRequiredAction(TermsRequiredActionFactory.PROVIDER_ID);

    context.success();
  }

  private static String firstOrDefault(List<String> values, String def) {
    return (values == null || values.isEmpty() || values.get(0) == null || values.get(0).isBlank()) ? def : values.get(0);
  }

  private static String safeUser(UserModel user) {
    try { return user.getUsername(); } catch (Exception e) { return "unknown"; }
  }

  @Override public void close() {}
}
