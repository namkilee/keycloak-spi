package com.example.keycloak.approval;

import org.jboss.logging.Logger;
import org.keycloak.authentication.AuthenticationFlowContext;
import org.keycloak.authentication.Authenticator;
import org.keycloak.models.*;

public class ApprovalGateAuthenticator implements Authenticator {
  private static final Logger LOG = Logger.getLogger(ApprovalGateAuthenticator.class);

  @Override
  public void authenticate(AuthenticationFlowContext context) {
    AuthenticationSessionModel authSession = context.getAuthenticationSession();
    ClientModel client = authSession.getClient();
    RealmModel realm = context.getRealm();
    UserModel user = context.getUser();

    if (client == null || user == null) {
      context.success();
      return;
    }

    String autoApprove = client.getAttribute(ApprovalConstants.ATTR_AUTO_APPROVE);
    boolean isAuto = "true".equalsIgnoreCase(autoApprove);

    boolean hasApproved = hasClientRole(user, client, ApprovalConstants.ROLE_APPROVED);

    // auth note: 어떤 client에 대한 승인 플로우인지 Required Action에서 다시 알 수 있게 저장
    authSession.setAuthNote(ApprovalConstants.NOTE_CLIENT_ID, client.getClientId());
    authSession.setAuthNote(ApprovalConstants.NOTE_CLIENT_UUID, client.getId());

    // (선택) 포털 URL을 client attribute로도 둘 수 있음: approval_portal_url 같은 키를 정하면 됨
    // authSession.setAuthNote(ApprovalConstants.NOTE_PORTAL_URL, client.getAttribute("approval_portal_url"));

    if (isAuto) {
      if (!hasApproved) {
        assignClientRole(user, client, ApprovalConstants.ROLE_APPROVED);
        LOG.infof("Auto-approved user=%s for client=%s", user.getUsername(), client.getClientId());
      }
      context.success();
      return;
    }

    // manual approve
    if (!hasApproved) {
      // Required Action을 user에 추가 → 로그인 후 Keycloak이 해당 화면으로 보냄
      user.addRequiredAction(ApprovalConstants.RA_ID);
      LOG.infof("Added required action '%s' for user=%s client=%s",
          ApprovalConstants.RA_ID, user.getUsername(), client.getClientId());
    }
    context.success();
  }

  private boolean hasClientRole(UserModel user, ClientModel client, String roleName) {
    RoleModel role = client.getRole(roleName);
    if (role == null) return false;
    return user.hasRole(role);
  }

  private void assignClientRole(UserModel user, ClientModel client, String roleName) {
    RoleModel role = client.getRole(roleName);
    if (role == null) {
      // role이 없으면 설계상 Terraform 누락이므로 경고만 남기고 통과/대기로 처리할지 정책 선택 가능
      LOG.warnf("Role '%s' not found on client '%s'", roleName, client.getClientId());
      return;
    }
    user.grantRole(role);
  }

  @Override public void action(AuthenticationFlowContext context) { context.success(); }
  @Override public boolean requiresUser() { return true; }
  @Override public boolean configuredFor(KeycloakSession session, RealmModel realm, UserModel user) { return true; }
  @Override public void setRequiredActions(KeycloakSession session, RealmModel realm, UserModel user) {}
  @Override public void close() {}
}
