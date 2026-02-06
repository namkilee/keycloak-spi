# Keycloak SPI Extensions

This repository contains a multi-module Maven project that delivers Keycloak Server Provider Interfaces (SPI) for:

- **Terms & Conditions Required Action** (`terms-ra`)
- **Value Transform Protocol Mapper** (`claim-mappers`)
- **User Info Sync SPI** (`user-info-sync`)

## Repository Structure

- `spi/`: Keycloak SPI 모듈 모음. 상세 내용은 [`spi/README.md`](spi/README.md)에서 확인한다.
- `keycloak-config/`: Keycloak Terraform 구성과 부트스트랩 정의. 하위 부트스트랩 문서는 [`keycloak-config/README.md`](keycloak-config/README.md) 및 [`keycloak-config/bootstrap/README.md`](keycloak-config/bootstrap/README.md)에 있다.
- `deploy/`: Docker 이미지, Helm 차트, 테마 배포 관련 리소스. 상세 내용은 [`deploy/README.md`](deploy/README.md)에서 확인한다.

## Modules

### Terms & Conditions Required Action (`terms-ra`)

This module provides a Required Action that forces users to accept one or more Terms & Conditions before continuing authentication.
Terms are configured via client-scope attributes and rendered in a custom FreeMarker login template.

#### Configuration (client scopes)

Terms are defined on client scopes using a single attribute:

- `tc.terms`: JSON array of term objects.

Each term object supports:

- `key`: Term identifier (required).
- `title`: Display title (defaults to `key`).
- `version`: Version string (required).
- `url`: Optional URL for the term document.
- `required`: `true|false` to mark as required (defaults to `false` when omitted).

**Scope resolution rules:**
1. Only client scopes with `tc.terms` are considered.
2. Scopes whose name starts with `shared-terms-` are treated as shared and loaded first.
3. Non-shared scopes override shared scopes when keys overlap.
4. Duplicate keys within the same layer (shared vs client-specific) cause a configuration error.

#### Acceptance storage

When a user accepts a term, the accepted version is stored on the user as:

```
tc.accepted.<clientId>.<termKey>
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
2. `mapping.api.*` (overrides DB mappings when the same key exists)
3. `mapping.db.*`
4. `mapping.file`
5. Client attribute `map.<source.user.attribute>` (if enabled)
6. Client attribute `mapping.client.key`

Cache keys are derived only from the mapper configuration values:
`source.user.attribute`, `mapping.inline`, `mapping.file`, `mapping.db.*`, `mapping.api.*`.
Cache policy settings (`mapping.cache.*`) and client attribute values are not part of the key.

### User Info Sync SPI (`user-info-sync`)

This module provides a scheduled task that synchronizes a user department attribute from a Knox REST API.
It supports multi-realm execution, realm attribute tuning, and cluster-safe once-per-day execution using a task key.

#### Environment variables

- `KNOX_API_URL`: Knox API endpoint (POST URL).
- `KNOX_SYSTEM_ID`: Knox system-id header value.
- `KNOX_API_TOKEN`: Knox bearer token (without the `Bearer ` prefix).

#### Realm attribute keys

- `userinfosync.enabled`: Enable sync (`true|false`).
- `userinfosync.runAt`: Run time in `HH:mm` (default `03:00`).
- `userinfosync.windowMinutes`: Allowed window in minutes (default `3`).
- `userinfosync.batchSize`: Paging batch size (default `500`).
- `userinfosync.resultType`: Knox result type (`basic|optional`, default `basic`).
- `userinfosync.httpTimeoutMs`: HTTP timeout in milliseconds (default `5000`).
- `userinfosync.maxConcurrency`: Parallel Knox calls (default `15`).
- `userinfosync.retry.maxAttempts`: Retry attempts for retryable errors (default `3`).
- `userinfosync.retry.baseBackoffMs`: Base backoff in milliseconds (default `250`).
- `userinfosync.taskKeyPrefix`: Cluster task key prefix (default `userinfosync`).
- `userinfosync.mappingJson`: JSON map of `{ userAttributeKey: knox.json.path }` (default `{"deptId":"response.employees.departmentCode"}`).
- `userinfosync.invalidateOnKeys`: Comma-separated attribute keys that trigger session invalidation (default `deptId`).

#### Sync behavior

- Task key is `userinfosync:{realmId}:{yyyyMMdd}` by default and uses cluster execution with a 26-hour TTL.
- When a user department changes, the SPI updates the attribute, sets `notBefore`, and logs out user sessions.

## Keycloak Terraform Config (keycloak-config)

Keycloak Terraform 구성은 `bootstrap`과 환경별(`dev|stg|prd`) 루트로 나뉜다.
`bootstrap`은 Terraform용 서비스 계정과 기본 Realm을 생성하고, 각 환경은 부트스트랩 상태를 원격 상태로 읽어 실제 Realm 구성과 클라이언트/스코프/IDP를 설정한다.

### 주요 개념

- **terms scope 설정**
  - 모든 환경에서 `clients[*].scopes.<scope>.tc_sets`로 약관 세트를 정의한다.
  - `tc_sets`는 client scope의 `tc.terms` JSON 배열로 동기화되며, 레거시 `terms_attributes` 방식은 더 이상 사용하지 않는다.
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
./mvnw -q -pl terms-ra,claim-mappers,user-info-sync -am package
```
