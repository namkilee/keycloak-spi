package com.example.keycloak.approval;

import org.jboss.logging.Logger;
import org.keycloak.authentication.AuthenticationFlowContext;
import org.keycloak.authentication.Authenticator;
import org.keycloak.authentication.AuthenticationFlowError;
import org.keycloak.forms.login.LoginFormsProvider;
import org.keycloak.models.*;

import jakarta.ws.rs.core.Response;

public class ApprovalGateAuthenticator implements Authenticator {
  private static final Logger LOG = Logger.getLogger(ApprovalGateAuthenticator.class);

  @Override
  public void authenticate(AuthenticationFlowContext context) {
    AuthenticationSessionModel authSession = context.getAuthenticationSession();
    ClientModel client = authSession.getClient();
    RealmModel realm = context.getRealm();
    UserModel user = context.getUser();

    // user 없는 케이스(예: 일부 브로커 단계)에서는 그냥 통과
    if (client == null || user == null) {
      context.success();
      return;
    }

    // 어떤 client에 대한 gate인지 (템플릿에서 사용 가능)
    authSession.setAuthNote(ApprovalConstants.NOTE_CLIENT_ID, client.getClientId());
    authSession.setAuthNote(ApprovalConstants.NOTE_CLIENT_UUID, client.getId());

    String autoApprove = client.getAttribute(ApprovalConstants.ATTR_AUTO_APPROVE);
    boolean isAuto = "true".equalsIgnoreCase(autoApprove);

    boolean hasApproved = hasClientRole(user, client, ApprovalConstants.ROLE_APPROVED);

    if (isAuto) {
      if (!hasApproved) {
        assignClientRole(user, client, ApprovalConstants.ROLE_APPROVED);
        LOG.infof("Auto-approved user=%s for client=%s", safe(user), client.getClientId());
      }
      context.success();
      return;
    }

    // manual approve
    if (hasApproved) {
      context.success();
      return;
    }

    // ✅ 여기부터가 핵심: RA 대신 Challenge로 "승인 대기" 페이지를 직접 띄움
    String portalUrl = client.getAttribute(ApprovalConstants.ATTR_PORTAL_URL); // e.g. "approval_portal_url"
    if (portalUrl == null || portalUrl.isBlank()) {
      // 포털 URL이 없으면 사용자에게 안내 페이지를 보여주거나, 에러로 막을지 선택
      portalUrl = ""; // 템플릿에서 조건 분기 가능
      LOG.warnf("Portal URL attribute '%s' missing on client=%s",
          ApprovalConstants.ATTR_PORTAL_URL, client.getClientId());
    }

    LoginFormsProvider form = context.form();
    form.setAttribute("clientId", client.getClientId());
    form.setAttribute("clientName", client.getName() != null ? client.getName() : client.getClientId());
    form.setAttribute("portalUrl", portalUrl);

    // 선택: 폴링/재시도 버튼 클릭 시 action()에서 처리하려면 hidden 값도 넣을 수 있음
    // form.setAttribute("retry", true);

    Response challenge = form.createForm("approval-pending.ftl");
    context.challenge(challenge);

    // ⚠️ 주의: challenge를 호출하면 이 단계에서 흐름이 멈춤
    LOG.infof("User pending approval: user=%s client=%s", safe(user), client.getClientId());
  }

  @Override
  public void action(AuthenticationFlowContext context) {
    // approval-pending.ftl 에서 POST로 "재시도" 버튼을 만들었다면 여기서 처리 가능
    // 기본은 그냥 다시 authenticate로 돌아가도 되지만, Keycloak이 다시 이 단계를 실행해줌.
    context.success();
  }

  private boolean hasClientRole(UserModel user, ClientModel client, String roleName) {
    RoleModel role = client.getRole(roleName);
    return role != null && user.hasRole(role);
  }

  private void assignClientRole(UserModel user, ClientModel client, String roleName) {
    RoleModel role = client.getRole(roleName);
    if (role == null) {
      LOG.warnf("Role '%s' not found on client '%s'", roleName, client.getClientId());
      return;
    }
    user.grantRole(role);
  }

  private String safe(UserModel user) {
    try { return user.getUsername(); } catch (Exception e) { return "(unknown)"; }
  }

  @Override public boolean requiresUser() { return true; }
  @Override public boolean configuredFor(KeycloakSession session, RealmModel realm, UserModel user) { return true; }
  @Override public void setRequiredActions(KeycloakSession session, RealmModel realm, UserModel user) {}
  @Override public void close() {}
}
