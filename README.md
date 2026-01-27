# Keycloak SPI Extensions

This repository contains a multi-module Maven project that delivers Keycloak Server Provider Interfaces (SPI) for:

- **Terms & Conditions Required Action** (`terms-ra`)
- **Value Transform Protocol Mapper** (`claim-mappers`)

## Repository Structure

- `spi/`: Keycloak SPI 모듈 모음. 상세 내용은 [`spi/README.md`](spi/README.md)에서 확인한다.
- `keycloak-config/`: Keycloak Terraform 구성과 부트스트랩 정의. 하위 부트스트랩 문서는 [`keycloak-config/README.md`](keycloak-config/README.md) 및 [`keycloak-config/bootstrap/README.md`](keycloak-config/bootstrap/README.md)에 있다.
- `deploy/`: Docker 이미지, Helm 차트, 테마 배포 관련 리소스. 상세 내용은 [`deploy/README.md`](deploy/README.md)에서 확인한다.

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

## Prerequisites

- Java 17 (see `spi/pom.xml` `<java.version>17</java.version>`).
- Keycloak 26.3.3 compatible (see `spi/pom.xml` `<keycloak.version>26.3.3</keycloak.version>`).
- Maven: use the project wrapper at `spi/mvnw` when building.

## Build

From the `spi` directory:

```
./mvnw -q -pl terms-ra,claim-mappers -am package
```
