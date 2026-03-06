package com.example.keycloak.approval;

public enum ApprovalStatus {
  APPROVED,
  PENDING,
  REJECTED;

  public static ApprovalStatus from(String value) {
    if (value == null || value.isBlank()) {
      return PENDING;
    }

    try {
      return ApprovalStatus.valueOf(value.trim().toUpperCase());
    } catch (IllegalArgumentException e) {
      return PENDING;
    }
  }
}