package com.example.keycloak.approval;

import jakarta.ws.rs.core.MultivaluedMap;
import org.jboss.logging.Logger;
import org.keycloak.authentication.RequiredActionContext;
import org.keycloak.authentication.RequiredActionProvider;
import org.keycloak.forms.login.LoginFormsProvider;
import org.keycloak.models.*;

public class ApprovalPendingRequiredAction implements RequiredActionProvider {
  private static final Logger LOG = Logger.getLogger(ApprovalPendingRequiredAction.class);

  @Override
  public void requiredActionChallenge(RequiredActionContext context) {
    if (isApprovedNow(context)) {
      context.getUser().removeRequiredAction(ApprovalConstants.RA_ID);
      context.success();
      return;
    }

    // 승인 대기 UI 렌더링
    String clientId = context.getAuthenticationSession().getAuthNote(ApprovalConstants.NOTE_CLIENT_ID);

    LoginFormsProvider forms = context.form();
    forms.setAttribute("clientId", clientId);
    // forms.setAttribute("portalUrl", context.getAuthenticationSession().getAuthNote(ApprovalConstants.NOTE_PORTAL_URL));

    context.challenge(forms.createForm("approval-pending.ftl"));
  }

  @Override
  public void processAction(RequiredActionContext context) {
    // 버튼 클릭 후 재검사
    if (isApprovedNow(context)) {
      context.getUser().removeRequiredAction(ApprovalConstants.RA_ID);
      context.success();
      return;
    }

    // 아직 승인 안 됨 → 같은 화면 재표시(에러 메시지)
    String clientId = context.getAuthenticationSession().getAuthNote(ApprovalConstants.NOTE_CLIENT_ID);

    LoginFormsProvider forms = context.form();
    forms.setAttribute("clientId", clientId);
    forms.setError("notApprovedYet"); // 메시지 키(테마에서 처리)
    context.challenge(forms.createForm("approval-pending.ftl"));
  }

  private boolean isApprovedNow(RequiredActionContext context) {
    AuthenticationSessionModel authSession = context.getAuthenticationSession();
    RealmModel realm = context.getRealm();
    UserModel user = context.getUser();

    String clientUuid = authSession.getAuthNote(ApprovalConstants.NOTE_CLIENT_UUID);
    if (clientUuid == null) {
      // auth note 없으면 현재 client로 fallback
      ClientModel client = authSession.getClient();
      if (client == null) return false;
      return hasClientRole(user, client, ApprovalConstants.ROLE_APPROVED);
    }

    ClientModel client = context.getSession().clients().getClientById(realm, clientUuid);
    if (client == null) return false;

    return hasClientRole(user, client, ApprovalConstants.ROLE_APPROVED);
  }

  private boolean hasClientRole(UserModel user, ClientModel client, String roleName) {
    RoleModel role = client.getRole(roleName);
    return role != null && user.hasRole(role);
  }

  @Override public void close() {}
}
