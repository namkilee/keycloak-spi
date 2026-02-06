package com.example.keycloak.terms;

import java.io.Serializable;
import java.util.List;

public final class TermsModels {
  private TermsModels() {}

  public record Term(
      String key,
      String title,
      String version,
      String url,
      boolean required
  ) implements Serializable {}

  public record TermsBundle(List<Term> terms) implements Serializable {}
}
