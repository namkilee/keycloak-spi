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
- `mapping.file`: File path or URL to a JSON mapping document.
- `mapping.db.enabled`: Enable mapping lookup from a SQL database.
- `mapping.db.jdbc.url`: JDBC URL for the mapping database.
- `mapping.db.username`: Database username.
- `mapping.db.password`: Database password.
- `mapping.db.query`: SQL query returning key/value columns for mapping.
- `mapping.api.enabled`: Enable mapping lookup from an HTTP API.
- `mapping.api.url`: API URL that returns JSON mapping.
- `mapping.api.auth.type`: API auth type (`none|bearer|basic|apikey`).
- `mapping.api.auth.token`: API token (bearer/api-key).
- `mapping.api.auth.user`: API basic auth username.
- `mapping.api.auth.password`: API basic auth password.
- `mapping.api.timeout.ms`: API timeout in milliseconds.
- `mapping.cache.enabled`: Cache merged mappings in memory.
- `mapping.cache.ttl.seconds`: Cache TTL in seconds.
- Cache key scope: Cache entries are shared across clients and mapper instances when the following config values match: `source.user.attribute`, `mapping.inline`, `mapping.file`, `mapping.db.*`, `mapping.api.*` (cache policy settings like `mapping.cache.*` do not affect the key).
- `mapping.client.autoKey`: If `true`, reads mapping from client attribute `map.<source.user.attribute>`.
- `mapping.client.key`: Manual/legacy client attribute key (used if auto-key is disabled or missing).
- `fallback.original`: If `true`, uses the original value when no mapping exists.
- `source.user.attribute.multi`: If `true`, maps all values from a multi-value user attribute and writes a list claim.

#### Mapping resolution order

Mappings are merged from lowest to highest priority. When the same key appears multiple times, higher-priority sources override lower ones.

Priority (highest → lowest):
1. `mapping.inline`
2. `mapping.api.*`
3. `mapping.db.*`
4. `mapping.file`
5. Client attribute `map.<source.user.attribute>` (if enabled)
6. Client attribute `mapping.client.key`

## Keycloak Terraform Config (keycloak-config)

Keycloak Terraform 구성은 `bootstrap`과 환경별(`dev|stg|prd`) 루트로 나뉜다.
`bootstrap`은 Terraform용 서비스 계정과 기본 Realm을 생성하고, 각 환경은 부트스트랩 상태를 원격 상태로 읽어 실제 Realm 구성과 클라이언트/스코프/IDP를 설정한다.

### 주요 개념

- **terms scope 설정**
  - **dev**: `clients[*].scopes.<scope>.tc_sets`로 여러 약관 세트를 정의할 수 있다.
  - **stg/prd**: `clients[*].scopes.<scope>.terms_attributes`로 단일 약관 세트를 정의한다(레거시 형식).
- **kcadm 실행 모드**
  - **dev**는 Docker 컨테이너 내부에서 `kcadm.sh`를 실행하며 `keycloak_container_name`이 필요하다.
  - **stg/prd**는 Kubernetes에서 `kubectl exec`를 사용하므로 `keycloak_namespace`, `keycloak_pod_selector`가 필요하다.
- **SAML IdP**
  - 모든 환경에서 SAML IdP 설정 및 매퍼 배열(`saml_idp_mappers`)을 지원한다.

### Terraform 변수 예시

필수/옵션 변수는 환경별 `terraform.tfvars.example`을 기준으로 관리한다.

- `keycloak-config/bootstrap/terraform.tfvars.example`
- `keycloak-config/dev/terraform.tfvars.example`
- `keycloak-config/stg/terraform.tfvars.example`
- `keycloak-config/prd/terraform.tfvars.example`

환경별 자세한 구조와 주의사항은 [`keycloak-config/README.md`](keycloak-config/README.md)를 참고한다.

## Prerequisites

- Java 17 (see `spi/pom.xml` `<java.version>17</java.version>`).
- Keycloak 26.3.3 compatible (see `spi/pom.xml` `<keycloak.version>26.3.3</keycloak.version>`).
- Maven: use the project wrapper at `spi/mvnw` when building.

## Build

From the `spi` directory:

```
./mvnw -q -pl terms-ra,claim-mappers -am package
```
