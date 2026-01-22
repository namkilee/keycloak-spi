package com.example.keycloak.mappers;

import com.fasterxml.jackson.core.type.TypeReference;
import org.keycloak.models.*;
import org.keycloak.protocol.oidc.mappers.AbstractOIDCProtocolMapper;
import org.keycloak.protocol.oidc.mappers.OIDCAccessTokenMapper;
import org.keycloak.protocol.oidc.mappers.OIDCAttributeMapperHelper;
import org.keycloak.protocol.oidc.mappers.OIDCIDTokenMapper;
import org.keycloak.protocol.oidc.mappers.UserInfoTokenMapper;
import org.keycloak.provider.ProviderConfigProperty;
import org.keycloak.representations.IDToken;
import org.keycloak.util.JsonSerialization;

import java.io.IOException;
import java.util.*;

public class ValueTransformProtocolMapper extends AbstractOIDCProtocolMapper
    implements OIDCAccessTokenMapper, OIDCIDTokenMapper, UserInfoTokenMapper {

  public static final String PROVIDER_ID = "value-transform-protocol-mapper";

  private static final String CFG_SOURCE_USER_ATTR = "source.user.attribute";
  private static final String CFG_TARGET_CLAIM = "target.claim.name";
  private static final String CFG_MAPPING_INLINE = "mapping.inline";
  private static final String CFG_USE_AUTO_CLIENT_KEY = "mapping.client.autoKey";
  private static final String CFG_CLIENT_ATTR_KEY = "mapping.client.key";
  private static final String CFG_FALLBACK_ORIGINAL = "fallback.original";

  private static final List<ProviderConfigProperty> CONFIG_PROPERTIES;

  static {
    List<ProviderConfigProperty> props = new ArrayList<>();

    ProviderConfigProperty p1 = new ProviderConfigProperty();
    p1.setName(CFG_SOURCE_USER_ATTR);
    p1.setLabel("Source user attribute");
    p1.setType(ProviderConfigProperty.STRING_TYPE);
    p1.setHelpText("UserModel attribute to read (e.g. dept_code, role_code).");
    p1.setDefaultValue("dept_code");
    props.add(p1);

    ProviderConfigProperty p2 = new ProviderConfigProperty();
    p2.setName(CFG_TARGET_CLAIM);
    p2.setLabel("Target claim name");
    p2.setType(ProviderConfigProperty.STRING_TYPE);
    p2.setHelpText("Claim name to write into tokens (e.g. dept, role).");
    p2.setDefaultValue("dept");
    props.add(p2);

    ProviderConfigProperty p3 = new ProviderConfigProperty();
    p3.setName(CFG_MAPPING_INLINE);
    p3.setLabel("Mapping (inline)");
    p3.setType(ProviderConfigProperty.TEXT_TYPE);
    p3.setHelpText("Mapping rules. CSV: A01:finance,A02:people OR JSON: {\"A01\":\"finance\"}. "
        + "If empty, reads mapping from client attributes.");
    props.add(p3);

    ProviderConfigProperty p4 = new ProviderConfigProperty();
    p4.setName(CFG_USE_AUTO_CLIENT_KEY);
    p4.setLabel("Use client attribute auto-key (map.<source>)");
    p4.setType(ProviderConfigProperty.BOOLEAN_TYPE);
    p4.setHelpText("If enabled, reads mapping from client attribute 'map.<source.user.attribute>' (e.g. map.dept_code).");
    p4.setDefaultValue("true");
    props.add(p4);

    ProviderConfigProperty p5 = new ProviderConfigProperty();
    p5.setName(CFG_CLIENT_ATTR_KEY);
    p5.setLabel("Client attribute key (manual/legacy)");
    p5.setType(ProviderConfigProperty.STRING_TYPE);
    p5.setHelpText("Client attribute key to load mapping from if auto-key is missing/disabled (e.g. dept.map).");
    p5.setDefaultValue("dept.map");
    props.add(p5);

    ProviderConfigProperty p6 = new ProviderConfigProperty();
    p6.setName(CFG_FALLBACK_ORIGINAL);
    p6.setLabel("Fallback to original value");
    p6.setType(ProviderConfigProperty.BOOLEAN_TYPE);
    p6.setHelpText("If no mapping found, use original value. If false, omit claim.");
    p6.setDefaultValue("true");
    props.add(p6);

    OIDCAttributeMapperHelper.addIncludeInTokensConfig(props, ValueTransformProtocolMapper.class);

    CONFIG_PROPERTIES = Collections.unmodifiableList(props);
  }

  @Override public String getId() { return PROVIDER_ID; }
  @Override public String getDisplayCategory() { return "Token mapper"; }
  @Override public String getDisplayType() { return "Value Transform (attribute -> claim)"; }
  @Override public String getHelpText() { return "Transforms a user attribute value via mapping rules and writes it as a claim."; }
  @Override public List<ProviderConfigProperty> getConfigProperties() { return CONFIG_PROPERTIES; }

  @Override
  protected void setClaim(IDToken token,
                          ProtocolMapperModel mapperModel,
                          UserSessionModel userSession,
                          KeycloakSession session,
                          ClientSessionContext clientSessionCtx) {

    UserModel user = userSession.getUser();

    String sourceAttr = getConfig(mapperModel, CFG_SOURCE_USER_ATTR, "dept_code");
    String targetClaim = getConfig(mapperModel, CFG_TARGET_CLAIM, "dept");

    String raw = user.getFirstAttribute(sourceAttr);
    if (raw == null || raw.isBlank()) return;

    Map<String, String> mapping = loadMapping(mapperModel, clientSessionCtx, sourceAttr);

    String mapped = mapping.get(raw);
    boolean fallbackOriginal = Boolean.parseBoolean(getConfig(mapperModel, CFG_FALLBACK_ORIGINAL, "true"));

    String finalValue;
    if (mapped != null && !mapped.isBlank()) {
      finalValue = mapped;
    } else if (fallbackOriginal) {
      finalValue = raw;
    } else {
      return;
    }

    token.getOtherClaims().put(targetClaim, finalValue);
  }

  private static String getConfig(ProtocolMapperModel model, String key, String defaultVal) {
    String v = model.getConfig() == null ? null : model.getConfig().get(key);
    return (v == null || v.isBlank()) ? defaultVal : v.trim();
  }

  private static Map<String, String> loadMapping(ProtocolMapperModel model,
                                                 ClientSessionContext ctx,
                                                 String sourceAttr) {
    // 1) inline mapping
    String inline = getConfig(model, CFG_MAPPING_INLINE, "");
    if (inline != null && !inline.isBlank()) {
      return parseMapping(inline);
    }

    ClientModel client = ctx.getClientSession().getClient();

    // 2) auto-key map.<sourceAttr>
    boolean useAutoKey = Boolean.parseBoolean(getConfig(model, CFG_USE_AUTO_CLIENT_KEY, "true"));
    if (useAutoKey) {
      String autoKey = "map." + sourceAttr;
      String v = client.getAttribute(autoKey);
      if (v != null && !v.isBlank()) return parseMapping(v);
    }

    // 3) manual/legacy key
    String manualKey = getConfig(model, CFG_CLIENT_ATTR_KEY, "dept.map");
    String mv = client.getAttribute(manualKey);
    if (mv != null && !mv.isBlank()) return parseMapping(mv);

    return Map.of();
  }

  private static Map<String, String> parseMapping(String raw) {
    String s = raw == null ? "" : raw.trim();
    if (s.isEmpty()) return Map.of();

    if (s.startsWith("{")) {
      try {
        Map<String, String> m = JsonSerialization.readValue(s, new TypeReference<Map<String, String>>() {});
        return (m == null) ? Map.of() : m;
      } catch (IOException e) {
        return Map.of();
      }
    }

    Map<String, String> map = new HashMap<>();
    String[] pairs = s.split(",");
    for (String pair : pairs) {
      String p = pair.trim();
      if (p.isEmpty()) continue;
      int idx = p.indexOf(':');
      if (idx <= 0 || idx == p.length() - 1) continue;
      String k = p.substring(0, idx).trim();
      String v = p.substring(idx + 1).trim();
      if (!k.isEmpty() && !v.isEmpty()) map.put(k, v);
    }
    return map;
  }
}
