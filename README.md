# Keycloak SPI Extensions

This repository contains a multi-module Maven project that delivers Keycloak Server Provider Interfaces (SPI) for:

- **Terms & Conditions Required Action** (`terms-ra`)
- **Value Transform Protocol Mapper** (`claim-mappers`)

## Modules

### Terms & Conditions Required Action (`terms-ra`)

This module provides a Required Action that forces users to accept one or more Terms & Conditions before continuing authentication.
Terms are configured via client or client-scope attributes and rendered in a custom FreeMarker login template.

#### Configuration keys

- `tc.required`: Comma-separated list of term IDs required for the client (e.g. `privacy,security`).
- `tc.term.<id>.title`: Display title for a term (defaults to `<id>`).
- `tc.term.<id>.version`: Version string (defaults to `unknown`).
- `tc.term.<id>.url`: Optional URL for a term document.
- `tc.term.<id>.required`: `true|false` to mark a term as required (defaults to `true`).

**Attribute lookup order:**
1. Client attributes
2. Client scope attributes (default scopes first, then optional scopes)

#### Acceptance storage

When a user accepts a term, acceptance is stored on the user as:

```
tc.accepted.<clientId>.<termId>.version
```

An acceptance timestamp is stored at:

```
tc.accepted.<clientId>.<termId>.version.at
```

### Value Transform Protocol Mapper (`claim-mappers`)

This module provides a protocol mapper that transforms a user attribute value into a token claim, using mapping rules supplied either inline or via client attributes.

#### Configuration keys

- `source.user.attribute`: User attribute to read (e.g. `dept_code`).
- `target.claim.name`: Claim name written to tokens.
- `mapping.inline`: Mapping rules inline. Supports:
  - CSV: `A01:finance,A02:people`
  - JSON: `{ "A01": "finance", "A02": "people" }`
- `mapping.client.autoKey`: If `true`, reads mapping from client attribute `map.<source.user.attribute>`.
- `mapping.client.key`: Manual/legacy client attribute key (used if auto-key is disabled or missing).
- `fallback.original`: If `true`, uses the original value when no mapping exists.
- `source.user.attribute.multi`: If `true`, maps all values from a multi-value user attribute and writes a list claim.

#### Mapping resolution order

1. `mapping.inline`
2. Client attribute `map.<source.user.attribute>` (if enabled)
3. Client attribute `mapping.client.key`

## Build

From the `spi` directory:

```
./mvnw -q -pl terms-ra,claim-mappers -am package
```
