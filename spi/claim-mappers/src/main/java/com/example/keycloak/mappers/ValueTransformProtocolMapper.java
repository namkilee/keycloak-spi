package com.example.keycloak.mappers;

import com.fasterxml.jackson.core.type.TypeReference;
import org.jboss.logging.Logger;
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
import java.io.InputStream;
import java.net.URL;
import java.nio.charset.StandardCharsets;
import java.nio.file.Files;
import java.nio.file.Path;
import java.util.*;

public class ValueTransformProtocolMapper extends AbstractOIDCProtocolMapper
    implements OIDCAccessTokenMapper, OIDCIDTokenMapper, UserInfoTokenMapper {

  public static final String PROVIDER_ID = "value-transform-protocol-mapper";

  private static final String CFG_SOURCE_USER_ATTR = "source.user.attribute";
  private static final String CFG_TARGET_CLAIM = "target.claim.name";
  private static final String CFG_MAPPING_INLINE = "mapping.inline";
  private static final String CFG_MAPPING_FILE = "mapping.file";
  private static final String CFG_USE_AUTO_CLIENT_KEY = "mapping.client.autoKey";
  private static final String CFG_CLIENT_ATTR_KEY = "mapping.client.key";
  private static final String CFG_FALLBACK_ORIGINAL = "fallback.original";
  private static final String CFG_MULTI_VALUE = "source.user.attribute.multi";

  private static final Logger LOG = Logger.getLogger(ValueTransformProtocolMapper.class);

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
        + "If empty, reads mapping from file/URL or client attributes.");
    props.add(p3);

    ProviderConfigProperty p4 = new ProviderConfigProperty();
    p4.setName(CFG_MAPPING_FILE);
    p4.setLabel("Mapping (file/URL)");
    p4.setType(ProviderConfigProperty.STRING_TYPE);
    p4.setHelpText("File path or URL pointing to a JSON map (e.g. /opt/keycloak/maps/dept.json). "
        + "If empty, reads mapping from client attributes.");
    props.add(p4);

    ProviderConfigProperty p5 = new ProviderConfigProperty();
    p5.setName(CFG_USE_AUTO_CLIENT_KEY);
    p5.setLabel("Use client attribute auto-key (map.<source>)");
    p5.setType(ProviderConfigProperty.BOOLEAN_TYPE);
    p5.setHelpText("If enabled, reads mapping from client attribute 'map.<source.user.attribute>' (e.g. map.dept_code).");
    p5.setDefaultValue("true");
    props.add(p5);

    ProviderConfigProperty p6 = new ProviderConfigProperty();
    p6.setName(CFG_CLIENT_ATTR_KEY);
    p6.setLabel("Client attribute key (manual/legacy)");
    p6.setType(ProviderConfigProperty.STRING_TYPE);
    p6.setHelpText("Client attribute key to load mapping from if auto-key is missing/disabled (e.g. dept.map).");
    p6.setDefaultValue("dept.map");
    props.add(p6);

    ProviderConfigProperty p7 = new ProviderConfigProperty();
    p7.setName(CFG_FALLBACK_ORIGINAL);
    p7.setLabel("Fallback to original value");
    p7.setType(ProviderConfigProperty.BOOLEAN_TYPE);
    p7.setHelpText("If no mapping found, use original value. If false, omit claim.");
    p7.setDefaultValue("true");
    props.add(p7);

    ProviderConfigProperty p8 = new ProviderConfigProperty();
    p8.setName(CFG_MULTI_VALUE);
    p8.setLabel("Allow multi-value source attribute");
    p8.setType(ProviderConfigProperty.BOOLEAN_TYPE);
    p8.setHelpText("If enabled, maps all values from a multi-value user attribute and writes a list claim.");
    p8.setDefaultValue("false");
    props.add(p8);

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
    boolean allowMulti = Boolean.parseBoolean(getConfig(mapperModel, CFG_MULTI_VALUE, "false"));

    List<String> rawValues = Optional.ofNullable(user.getAttributes().get(sourceAttr))
        .orElse(List.of());
    if (rawValues.isEmpty()) return;

    Map<String, String> mapping = loadMapping(mapperModel, clientSessionCtx, sourceAttr);

    boolean fallbackOriginal = Boolean.parseBoolean(getConfig(mapperModel, CFG_FALLBACK_ORIGINAL, "true"));

    if (!allowMulti) {
      String raw = rawValues.get(0);
      if (raw == null || raw.isBlank()) return;
      String mapped = mapping.get(raw);

      String finalValue;
      if (mapped != null && !mapped.isBlank()) {
        finalValue = mapped;
      } else if (fallbackOriginal) {
        finalValue = raw;
      } else {
        return;
      }
      token.getOtherClaims().put(targetClaim, finalValue);
      return;
    }

    List<String> mappedValues = new ArrayList<>();
    for (String raw : rawValues) {
      if (raw == null || raw.isBlank()) continue;
      String mapped = mapping.get(raw);
      if (mapped != null && !mapped.isBlank()) {
        mappedValues.add(mapped);
      } else if (fallbackOriginal) {
        mappedValues.add(raw);
      }
    }

    if (!mappedValues.isEmpty()) {
      token.getOtherClaims().put(targetClaim, mappedValues);
    }
  }

  private static String getConfig(ProtocolMapperModel model, String key, String defaultVal) {
    String v = model.getConfig() == null ? null : model.getConfig().get(key);
    return (v == null || v.isBlank()) ? defaultVal : v.trim();
  }

  private static Map<String, String> loadMapping(ProtocolMapperModel model,
                                                 ClientSessionContext ctx,
                                                 String sourceAttr) {
    Map<String, String> merged = new LinkedHashMap<>();

    ClientModel client = ctx.getClientSession().getClient();

    // 4) manual/legacy key (lowest priority)
    String manualKey = getConfig(model, CFG_CLIENT_ATTR_KEY, "dept.map");
    String mv = client.getAttribute(manualKey);
    if (mv != null && !mv.isBlank()) {
      merged.putAll(parseMapping(mv));
    }

    // 3) auto-key map.<sourceAttr>
    boolean useAutoKey = Boolean.parseBoolean(getConfig(model, CFG_USE_AUTO_CLIENT_KEY, "true"));
    if (useAutoKey) {
      String autoKey = "map." + sourceAttr;
      String v = client.getAttribute(autoKey);
      if (v != null && !v.isBlank()) {
        merged.putAll(parseMapping(v));
      }
    }

    // 2) mapping file/URL
    String mappingFile = getConfig(model, CFG_MAPPING_FILE, "");
    if (mappingFile != null && !mappingFile.isBlank()) {
      merged.putAll(readMappingFile(mappingFile));
    }

    // 1) inline mapping (highest priority)
    String inline = getConfig(model, CFG_MAPPING_INLINE, "");
    if (inline != null && !inline.isBlank()) {
      merged.putAll(parseMapping(inline));
    }

    return merged.isEmpty() ? Map.of() : merged;
  }

  private static Map<String, String> readMappingFile(String location) {
    String trimmed = location == null ? "" : location.trim();
    if (trimmed.isEmpty()) return Map.of();

    try {
      String json;
      if (trimmed.startsWith("http://") || trimmed.startsWith("https://") || trimmed.startsWith("file:")) {
        try (InputStream in = new URL(trimmed).openStream()) {
          json = new String(in.readAllBytes(), StandardCharsets.UTF_8);
        }
      } else {
        json = Files.readString(Path.of(trimmed), StandardCharsets.UTF_8);
      }
      if (json == null || json.isBlank()) return Map.of();

      Map<String, String> m = JsonSerialization.readValue(json, new TypeReference<Map<String, String>>() {});
      return (m == null) ? Map.of() : m;
    } catch (IOException e) {
      LOG.warnf("Failed to read JSON mapping from '%s': %s", trimmed, e.getMessage());
      return Map.of();
    }
  }

  private static Map<String, String> parseMapping(String raw) {
    String s = raw == null ? "" : raw.trim();
    if (s.isEmpty()) return Map.of();

    if (s.startsWith("{")) {
      try {
        Map<String, String> m = JsonSerialization.readValue(s, new TypeReference<Map<String, String>>() {});
        return (m == null) ? Map.of() : m;
      } catch (IOException e) {
        LOG.warnf("Failed to parse JSON mapping for protocol mapper: %s", e.getMessage());
        return Map.of();
      }
    }

    Map<String, String> map = new HashMap<>();
    String[] pairs = s.split(",");
    for (String pair : pairs) {
      String p = pair.trim();
      if (p.isEmpty()) continue;
      int idx = p.indexOf(':');
      if (idx <= 0 || idx == p.length() - 1) {
        LOG.warnf("Skipping malformed mapping pair: '%s'", p);
        continue;
      }
      String k = p.substring(0, idx).trim();
      String v = p.substring(idx + 1).trim();
      if (!k.isEmpty() && !v.isEmpty()) map.put(k, v);
    }
    return map;
  }
}
