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
import java.net.HttpURLConnection;
import java.nio.charset.StandardCharsets;
import java.nio.file.Files;
import java.nio.file.Path;
import java.sql.Connection;
import java.sql.DriverManager;
import java.sql.ResultSet;
import java.sql.SQLException;
import java.sql.Statement;
import java.time.Duration;
import java.util.*;
import java.util.concurrent.ConcurrentHashMap;

public class ValueTransformProtocolMapper extends AbstractOIDCProtocolMapper
    implements OIDCAccessTokenMapper, OIDCIDTokenMapper, UserInfoTokenMapper {

  public static final String PROVIDER_ID = "value-transform-protocol-mapper";

  private static final String CFG_SOURCE_USER_ATTR = "source.user.attribute";
  private static final String CFG_TARGET_CLAIM = "target.claim.name";
  private static final String CFG_MAPPING_INLINE = "mapping.inline";
  private static final String CFG_MAPPING_FILE = "mapping.file";

  private static final String CFG_MAPPING_DB_ENABLED = "mapping.db.enabled";
  private static final String CFG_MAPPING_DB_JDBC_URL = "mapping.db.jdbc.url";
  private static final String CFG_MAPPING_DB_USERNAME = "mapping.db.username";
  private static final String CFG_MAPPING_DB_PASSWORD = "mapping.db.password";
  private static final String CFG_MAPPING_DB_QUERY = "mapping.db.query";
  private static final String CFG_MAPPING_API_ENABLED = "mapping.api.enabled";
  private static final String CFG_MAPPING_API_URL = "mapping.api.url";
  private static final String CFG_MAPPING_API_AUTH_TYPE = "mapping.api.auth.type";
  private static final String CFG_MAPPING_API_AUTH_TOKEN = "mapping.api.auth.token";
  private static final String CFG_MAPPING_API_AUTH_USER = "mapping.api.auth.user";
  private static final String CFG_MAPPING_API_AUTH_PASSWORD = "mapping.api.auth.password";
  private static final String CFG_MAPPING_API_TIMEOUT_MS = "mapping.api.timeout.ms";
  private static final String CFG_MAPPING_CACHE_ENABLED = "mapping.cache.enabled";
  private static final String CFG_MAPPING_CACHE_TTL_SECONDS = "mapping.cache.ttl.seconds";
  private static final String CFG_USE_AUTO_CLIENT_KEY = "mapping.client.autoKey";
  private static final String CFG_CLIENT_ATTR_KEY = "mapping.client.key";
  private static final String CFG_FALLBACK_ORIGINAL = "fallback.original";
  private static final String CFG_MULTI_VALUE = "source.user.attribute.multi";

  private static final Logger LOG = Logger.getLogger(ValueTransformProtocolMapper.class);
  private static final Map<String, CacheEntry> MAPPING_CACHE = new ConcurrentHashMap<>();

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

    p5.setName(CFG_MAPPING_DB_ENABLED);
    p5.setLabel("Mapping (DB enabled)");
    p5.setType(ProviderConfigProperty.BOOLEAN_TYPE);
    p5.setHelpText("If enabled, loads mapping rows from a SQL query.");
    p5.setDefaultValue("false");
    props.add(p5);

    ProviderConfigProperty p6 = new ProviderConfigProperty();
    p6.setName(CFG_MAPPING_DB_JDBC_URL);
    p6.setLabel("Mapping DB JDBC URL");
    p6.setType(ProviderConfigProperty.STRING_TYPE);
    p6.setHelpText("JDBC URL for mapping DB (e.g. jdbc:postgresql://db:5432/app).");
    props.add(p6);

    ProviderConfigProperty p7 = new ProviderConfigProperty();
    p7.setName(CFG_MAPPING_DB_USERNAME);
    p7.setLabel("Mapping DB username");
    p7.setType(ProviderConfigProperty.STRING_TYPE);
    p7.setHelpText("DB username for mapping lookup.");
    props.add(p7);

    ProviderConfigProperty p8 = new ProviderConfigProperty();
    p8.setName(CFG_MAPPING_DB_PASSWORD);
    p8.setLabel("Mapping DB password");
    p8.setType(ProviderConfigProperty.PASSWORD);
    p8.setHelpText("DB password for mapping lookup.");
    props.add(p8);

    ProviderConfigProperty p9 = new ProviderConfigProperty();
    p9.setName(CFG_MAPPING_DB_QUERY);
    p9.setLabel("Mapping DB query");
    p9.setType(ProviderConfigProperty.STRING_TYPE);
    p9.setHelpText("SQL query that returns key/value columns for mapping.");
    props.add(p9);

    ProviderConfigProperty p10 = new ProviderConfigProperty();
    p10.setName(CFG_MAPPING_API_ENABLED);
    p10.setLabel("Mapping (API enabled)");
    p10.setType(ProviderConfigProperty.BOOLEAN_TYPE);
    p10.setHelpText("If enabled, loads mapping from an HTTP API returning JSON map.");
    p10.setDefaultValue("false");
    props.add(p10);

    ProviderConfigProperty p11 = new ProviderConfigProperty();
    p11.setName(CFG_MAPPING_API_URL);
    p11.setLabel("Mapping API URL");
    p11.setType(ProviderConfigProperty.STRING_TYPE);
    p11.setHelpText("HTTP(S) URL that returns JSON mapping.");
    props.add(p11);

    ProviderConfigProperty p12 = new ProviderConfigProperty();
    p12.setName(CFG_MAPPING_API_AUTH_TYPE);
    p12.setLabel("Mapping API auth type");
    p12.setType(ProviderConfigProperty.STRING_TYPE);
    p12.setHelpText("Auth type: none|bearer|basic|apikey.");
    p12.setDefaultValue("none");
    props.add(p12);

    ProviderConfigProperty p13 = new ProviderConfigProperty();
    p13.setName(CFG_MAPPING_API_AUTH_TOKEN);
    p13.setLabel("Mapping API auth token");
    p13.setType(ProviderConfigProperty.PASSWORD);
    p13.setHelpText("Bearer token or API key value.");
    props.add(p13);

    ProviderConfigProperty p14 = new ProviderConfigProperty();
    p14.setName(CFG_MAPPING_API_AUTH_USER);
    p14.setLabel("Mapping API auth user");
    p14.setType(ProviderConfigProperty.STRING_TYPE);
    p14.setHelpText("Basic auth username.");
    props.add(p14);

    ProviderConfigProperty p15 = new ProviderConfigProperty();
    p15.setName(CFG_MAPPING_API_AUTH_PASSWORD);
    p15.setLabel("Mapping API auth password");
    p15.setType(ProviderConfigProperty.PASSWORD);
    p15.setHelpText("Basic auth password.");
    props.add(p15);

    ProviderConfigProperty p16 = new ProviderConfigProperty();
    p16.setName(CFG_MAPPING_API_TIMEOUT_MS);
    p16.setLabel("Mapping API timeout (ms)");
    p16.setType(ProviderConfigProperty.STRING_TYPE);
    p16.setHelpText("HTTP timeout in milliseconds.");
    p16.setDefaultValue("3000");
    props.add(p16);

    ProviderConfigProperty p17 = new ProviderConfigProperty();
    p17.setName(CFG_MAPPING_CACHE_ENABLED);
    p17.setLabel("Mapping cache enabled");
    p17.setType(ProviderConfigProperty.BOOLEAN_TYPE);
    p17.setHelpText("Cache merged mapping in memory to reduce DB/API calls.");
    p17.setDefaultValue("true");
    props.add(p17);

    ProviderConfigProperty p18 = new ProviderConfigProperty();
    p18.setName(CFG_MAPPING_CACHE_TTL_SECONDS);
    p18.setLabel("Mapping cache TTL (seconds)");
    p18.setType(ProviderConfigProperty.STRING_TYPE);
    p18.setHelpText("Cache time-to-live in seconds.");
    p18.setDefaultValue("300");
    props.add(p18);

    ProviderConfigProperty p19 = new ProviderConfigProperty();
    p19.setName(CFG_USE_AUTO_CLIENT_KEY);
    p19.setLabel("Use client attribute auto-key (map.<source>)");
    p19.setType(ProviderConfigProperty.BOOLEAN_TYPE);
    p19.setHelpText("If enabled, reads mapping from client attribute 'map.<source.user.attribute>' (e.g. map.dept_code).");
    p19.setDefaultValue("true");
    props.add(p19);

    ProviderConfigProperty p20 = new ProviderConfigProperty();
    p20.setName(CFG_CLIENT_ATTR_KEY);
    p20.setLabel("Client attribute key (manual/legacy)");
    p20.setType(ProviderConfigProperty.STRING_TYPE);
    p20.setHelpText("Client attribute key to load mapping from if auto-key is missing/disabled (e.g. dept.map).");
    p20.setDefaultValue("dept.map");
    props.add(p20);

    ProviderConfigProperty p21 = new ProviderConfigProperty();
    p21.setName(CFG_FALLBACK_ORIGINAL);
    p21.setLabel("Fallback to original value");
    p21.setType(ProviderConfigProperty.BOOLEAN_TYPE);
    p21.setHelpText("If no mapping found, use original value. If false, omit claim.");
    p21.setDefaultValue("true");
    props.add(p21);

    ProviderConfigProperty p22 = new ProviderConfigProperty();
    p22.setName(CFG_MULTI_VALUE);
    p22.setLabel("Allow multi-value source attribute");
    p22.setType(ProviderConfigProperty.BOOLEAN_TYPE);
    p22.setHelpText("If enabled, maps all values from a multi-value user attribute and writes a list claim.");
    p22.setDefaultValue("false");
    props.add(p22);

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
    boolean cacheEnabled = Boolean.parseBoolean(getConfig(model, CFG_MAPPING_CACHE_ENABLED, "true"));
    String cacheKey = cacheKey(model, ctx.getClientSession().getClient(), sourceAttr);
    if (cacheEnabled) {
      Map<String, String> cached = getCachedMapping(model, cacheKey);
      if (cached != null) {
        return cached;
      }
    }

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

    // 2.5) DB / API mapping (higher than file)
    merged.putAll(readMappingDb(model));
    merged.putAll(readMappingApi(model));

    // 1) inline mapping (highest priority)
    String inline = getConfig(model, CFG_MAPPING_INLINE, "");
    if (inline != null && !inline.isBlank()) {
      merged.putAll(parseMapping(inline));
    }

    Map<String, String> finalMapping = merged.isEmpty() ? Map.of() : merged;
    if (cacheEnabled) {
      putCachedMapping(model, cacheKey, finalMapping);
    }
    return finalMapping;
  }

  private static String cacheKey(ProtocolMapperModel model, ClientModel client, String sourceAttr) {
    String mapperId = model.getId() == null ? "unknown" : model.getId();
    String clientId = client.getClientId() == null ? "unknown" : client.getClientId();
    int configHash = model.getConfig() == null ? 0 : model.getConfig().hashCode();
    return mapperId + ":" + clientId + ":" + sourceAttr + ":" + configHash;
  }

  private static Map<String, String> getCachedMapping(ProtocolMapperModel model, String cacheKey) {
    CacheEntry entry = MAPPING_CACHE.get(cacheKey);
    if (entry == null) return null;
    if (entry.expiresAtMs < System.currentTimeMillis()) {
      MAPPING_CACHE.remove(cacheKey);
      return null;
    }
    return entry.mapping;
  }

  private static void putCachedMapping(ProtocolMapperModel model, String cacheKey, Map<String, String> mapping) {
    long ttlSeconds = parseLong(getConfig(model, CFG_MAPPING_CACHE_TTL_SECONDS, "300"), 300);
    long ttlMs = Duration.ofSeconds(ttlSeconds).toMillis();
    long expiresAt = System.currentTimeMillis() + ttlMs;
    MAPPING_CACHE.put(cacheKey, new CacheEntry(mapping, expiresAt));
  }

  private static Map<String, String> readMappingDb(ProtocolMapperModel model) {
    boolean enabled = Boolean.parseBoolean(getConfig(model, CFG_MAPPING_DB_ENABLED, "false"));
    if (!enabled) return Map.of();

    String jdbcUrl = getConfig(model, CFG_MAPPING_DB_JDBC_URL, "");
    String username = getConfig(model, CFG_MAPPING_DB_USERNAME, "");
    String password = getConfig(model, CFG_MAPPING_DB_PASSWORD, "");
    String query = getConfig(model, CFG_MAPPING_DB_QUERY, "");
    if (jdbcUrl.isBlank() || query.isBlank()) return Map.of();

    Map<String, String> results = new LinkedHashMap<>();
    try (Connection conn = DriverManager.getConnection(jdbcUrl, username, password);
         Statement stmt = conn.createStatement();
         ResultSet rs = stmt.executeQuery(query)) {
      while (rs.next()) {
        String key = rs.getString(1);
        String value = rs.getString(2);
        if (key != null && value != null) {
          results.put(key, value);
        }
      }
    } catch (SQLException e) {
      LOG.warnf("Failed to load DB mapping: %s", e.getMessage());
      return Map.of();
    }
    return results;
  }

  private static Map<String, String> readMappingApi(ProtocolMapperModel model) {
    boolean enabled = Boolean.parseBoolean(getConfig(model, CFG_MAPPING_API_ENABLED, "false"));
    if (!enabled) return Map.of();

    String apiUrl = getConfig(model, CFG_MAPPING_API_URL, "");
    if (apiUrl.isBlank()) return Map.of();

    int timeoutMs = (int) parseLong(getConfig(model, CFG_MAPPING_API_TIMEOUT_MS, "3000"), 3000);
    try {
      HttpURLConnection conn = (HttpURLConnection) new URL(apiUrl).openConnection();
      conn.setRequestMethod("GET");
      conn.setConnectTimeout(timeoutMs);
      conn.setReadTimeout(timeoutMs);

      String authType = getConfig(model, CFG_MAPPING_API_AUTH_TYPE, "none").toLowerCase(Locale.ROOT);
      if ("bearer".equals(authType)) {
        String token = getConfig(model, CFG_MAPPING_API_AUTH_TOKEN, "");
        if (!token.isBlank()) {
          conn.setRequestProperty("Authorization", "Bearer " + token);
        }
      } else if ("basic".equals(authType)) {
        String user = getConfig(model, CFG_MAPPING_API_AUTH_USER, "");
        String pass = getConfig(model, CFG_MAPPING_API_AUTH_PASSWORD, "");
        String encoded = Base64.getEncoder().encodeToString((user + ":" + pass).getBytes(StandardCharsets.UTF_8));
        conn.setRequestProperty("Authorization", "Basic " + encoded);
      } else if ("apikey".equals(authType)) {
        String token = getConfig(model, CFG_MAPPING_API_AUTH_TOKEN, "");
        if (!token.isBlank()) {
          conn.setRequestProperty("X-API-Key", token);
        }
      }

      int status = conn.getResponseCode();
      if (status < 200 || status >= 300) {
        LOG.warnf("Mapping API returned status %d", status);
        return Map.of();
      }

      try (InputStream in = conn.getInputStream()) {
        String json = new String(in.readAllBytes(), StandardCharsets.UTF_8);
        if (json.isBlank()) return Map.of();
        Map<String, String> m = JsonSerialization.readValue(json, new TypeReference<Map<String, String>>() {});
        return (m == null) ? Map.of() : m;
      }
    } catch (IOException e) {
      LOG.warnf("Failed to read mapping from API: %s", e.getMessage());
      return Map.of();
    }
  }

  private static long parseLong(String raw, long defaultValue) {
    try {
      return Long.parseLong(raw);
    } catch (NumberFormatException e) {
      return defaultValue;
    }
  }

  private static final class CacheEntry {
    private final Map<String, String> mapping;
    private final long expiresAtMs;

    private CacheEntry(Map<String, String> mapping, long expiresAtMs) {
      this.mapping = mapping;
      this.expiresAtMs = expiresAtMs;
    }
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
