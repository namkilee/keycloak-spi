package com.example.keycloak.userinfosync;

import com.fasterxml.jackson.databind.JsonNode;
import com.fasterxml.jackson.databind.ObjectMapper;

public record KnoxUserInfo(String departmentCode) {

  private static final ObjectMapper OM = new ObjectMapper();

  public static KnoxUserInfo fromJson(String json) {
    try {
      JsonNode root = OM.readTree(json);
      JsonNode employees = root.path("response").path("employees");

      String dept = null;
      if (employees.isObject()) {
        dept = employees.path("departmentCode").asText(null);
      } else if (employees.isArray() && !employees.isEmpty()) {
        dept = employees.get(0).path("departmentCode").asText(null);
      }

      if (dept == null || dept.isBlank()) {
        throw new IllegalArgumentException("Missing response.employees.departmentCode");
      }
      return new KnoxUserInfo(dept);
    } catch (Exception e) {
      throw new RuntimeException("Failed to parse Knox JSON", e);
    }
  }
}
