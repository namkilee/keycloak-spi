package com.example.keycloak.approval;

public final class ApprovalConstants {
  private ApprovalConstants() {}

  public static final String ATTR_AUTO_APPROVE = "auto_approve";
  public static final String ROLE_APPROVED = "approved";

  // auth note keys
  public static final String NOTE_CLIENT_ID = "approval.client_id";
  public static final String NOTE_CLIENT_UUID = "approval.client_uuid"; // internal id
  public static final String NOTE_PORTAL_URL = "approval.portal_url";   // optional
}
