package com.example.keycloak.approval;

import jakarta.ws.rs.core.MultivaluedMap;
import jakarta.ws.rs.core.Response;
import org.jboss.logging.Logger;
import org.keycloak.authentication.RequiredActionContext;
import org.keycloak.authentication.RequiredActionProvider;
import org.keycloak.forms.login.LoginFormsProvider;
import org.keycloak.models.AuthenticationSessionModel;
import org.keycloak.models.ClientModel;
import org.keycloak.models.KeycloakSession;
import org.keycloak.models.UserModel;

public class ApprovalRequiredActionProvider implements RequiredActionProvider {
  private static final Logger LOG = Logger.getLogger(ApprovalRequiredActionProvider.class);

  private final KeycloakSession session;

  public ApprovalRequiredActionProvider(KeycloakSession session) {
    this.session = session;
  }

  @Override
  public void evaluateTriggers(RequiredActionContext context) {
    AuthenticationSessionModel authSession = context.getAuthenticationSession();
    ClientModel client = authSession != null ? authSession.getClient() : null;
    UserModel user = context.getUser();

    if (client == null || user == null) {
      return;
    }

    rememberClientInfo(authSession, client);

    ApprovalStatus status = getApprovalStatus(user, client);
    rememberApprovalStatus(authSession, status);

    if (status == ApprovalStatus.APPROVED) {
      user.removeRequiredAction(ApprovalConstants.RA_PROVIDER_ID);
      LOG.debugf("Approval already granted: user=%s client=%s", safe(user), client.getClientId());
      return;
    }

    user.addRequiredAction(ApprovalConstants.RA_PROVIDER_ID);
    LOG.debugf("Approval required: user=%s client=%s status=%s",
        safe(user), client.getClientId(), status.name());
  }

  @Override
  public void requiredActionChallenge(RequiredActionContext context) {
    AuthenticationSessionModel authSession = context.getAuthenticationSession();
    ClientModel client = authSession != null ? authSession.getClient() : null;
    UserModel user = context.getUser();

    if (client == null || user == null) {
      context.success();
      return;
    }

    rememberClientInfo(authSession, client);

    ApprovalStatus status = getApprovalStatus(user, client);
    rememberApprovalStatus(authSession, status);

    if (status == ApprovalStatus.APPROVED) {
      user.removeRequiredAction(ApprovalConstants.RA_PROVIDER_ID);
      context.success();
      LOG.infof("Approval completed immediately: user=%s client=%s", safe(user), client.getClientId());
      return;
    }

    Response challenge = buildChallenge(context, client, status, false);
    context.challenge(challenge);

    LOG.infof("User pending approval: user=%s client=%s status=%s",
        safe(user), client.getClientId(), status.name());
  }

  @Override
  public void processAction(RequiredActionContext context) {
    AuthenticationSessionModel authSession = context.getAuthenticationSession();
    ClientModel client = authSession != null ? authSession.getClient() : null;
    UserModel user = context.getUser();

    if (client == null || user == null) {
      context.success();
      return;
    }

    rememberClientInfo(authSession, client);

    MultivaluedMap<String, String> formData = context.getHttpRequest().getDecodedFormParameters();
    String action = formData != null ? formData.getFirst("action") : null;
    boolean retried = "retry".equals(action);

    ApprovalStatus status = getApprovalStatus(user, client);
    rememberApprovalStatus(authSession, status);

    if (status == ApprovalStatus.APPROVED) {
      user.removeRequiredAction(ApprovalConstants.RA_PROVIDER_ID);
      context.success();
      LOG.infof("Approval confirmed after retry: user=%s client=%s", safe(user), client.getClientId());
      return;
    }

    Response challenge = buildChallenge(context, client, status, retried);
    context.challenge(challenge);
  }

  private Response buildChallenge(
      RequiredActionContext context,
      ClientModel client,
      ApprovalStatus status,
      boolean retried
  ) {
    String portalUrl = client.getAttribute(ApprovalConstants.ATTR_PORTAL_URL);
    if (portalUrl == null) {
      portalUrl = "";
    }

    LoginFormsProvider form = context.form();
    form.setAttribute("clientId", client.getClientId());
    form.setAttribute("clientName", client.getName() != null ? client.getName() : client.getClientId());
    form.setAttribute("portalUrl", portalUrl);
    form.setAttribute("approvalStatus", status.name());

    if (status == ApprovalStatus.REJECTED) {
      form.setError("승인이 거절되었습니다. 관리자에게 문의해 주세요.");
    } else if (retried) {
      form.setError("아직 승인이 완료되지 않았습니다.");
    }

    return form.createForm("approval-pending.ftl");
  }

  private ApprovalStatus getApprovalStatus(UserModel user, ClientModel client) {
    String key = approvalAttributeKey(client.getClientId());
    String raw = user.getFirstAttribute(key);
    return ApprovalStatus.from(raw);
  }

  private String approvalAttributeKey(String clientId) {
    return ApprovalConstants.ATTR_APPROVAL_PREFIX + clientId;
  }

  private void rememberClientInfo(AuthenticationSessionModel authSession, ClientModel client) {
    if (authSession == null || client == null) {
      return;
    }

    authSession.setAuthNote(ApprovalConstants.NOTE_CLIENT_ID, client.getClientId());
    authSession.setAuthNote(ApprovalConstants.NOTE_CLIENT_UUID, client.getId());

    String portalUrl = client.getAttribute(ApprovalConstants.ATTR_PORTAL_URL);
    if (portalUrl != null) {
      authSession.setAuthNote(ApprovalConstants.NOTE_PORTAL_URL, portalUrl);
    }
  }

  private void rememberApprovalStatus(AuthenticationSessionModel authSession, ApprovalStatus status) {
    if (authSession == null || status == null) {
      return;
    }
    authSession.setAuthNote(ApprovalConstants.NOTE_APPROVAL_STATUS, status.name());
  }

  private String safe(UserModel user) {
    try {
      return user.getUsername();
    } catch (Exception e) {
      return "(unknown)";
    }
  }

  @Override
  public void close() {
  }
}