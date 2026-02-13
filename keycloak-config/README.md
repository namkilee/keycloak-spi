# Keycloak Terraform Config

이 디렉터리는 Keycloak 리소스를 Terraform으로 관리하기 위한 코드 모음이다.

## 디렉터리 구조

- `modules/realm-clients`
  - 서비스 OIDC client 생성
  - shared/client scope 연결
  - required action(`terms-required-action`) 등록
  - approval 포털 client + approver role + post-broker flow 구성
  - SAML IdP 및 mapper 구성
- `modules/scopes`
  - client-specific / shared OpenID client scope 생성
  - generic protocol mapper 생성
  - `tc_sets`를 `kcadm` 기반 스크립트로 scope attribute(`tc.<termKey>.*`) 동기화
- `modules/realm-userinfo-sync`
  - realm attribute `userinfosync.*` 출력값 생성
- `infra/bootstrap`
  - bootstrap realm + terraform client 생성
  - bootstrap state를 환경 루트에서 참조
- `infra/dev`, `infra/stg`, `infra/prd`
  - 환경별 루트 모듈
  - bootstrap 원격 상태를 읽어 실제 realm/client/scope/idp를 적용

## 핵심 동작

### 1) 약관 데이터(`tc_sets`) 동기화

`clients[*].scopes[*].tc_sets` 및 `shared_scopes[*].tc_sets`를 선언하면,
`modules/scopes`가 JSON payload를 만들어 스크립트(`modules/scopes/scripts/tc/tc_sync_scopes.sh`)를 실행한다.

실행 모드:
- dev: `docker exec`
- stg/prd: `kubectl exec`

결과적으로 client scope attribute는 `tc.<termKey>.<field>` 형태로 기록되며,
`terms-action` SPI가 이를 읽는다.

### 2) 승인 게이트(Access Approval)

`modules/realm-clients`는 아래를 자동 구성한다.

- 서비스 client attribute
  - `auto_approve`
  - `approval_portal_url`
- 서비스 client role
  - `approved`
- `approval-portal` client (service account enabled)
- post-broker flow에서 `approval-gate-authenticator` 실행

### 3) UserInfoSync realm attributes

`modules/realm-userinfo-sync`는 realm attribute 키(예: `userinfosync.enabled`, `userinfosync.mappingJson`)를 출력한다.
실제 Knox API 호출에 필요한 비밀 값(`KNOX_*`)은 Terraform 변수 대신 런타임 환경변수로 주입해야 한다.

## 사용 순서

1. `infra/bootstrap` 적용 (realm + terraform client 준비)
2. 대상 환경(`infra/dev|stg|prd`)에서 `terraform init`
3. 환경별 `terraform.tfvars.example` 기반으로 값 설정
4. `terraform apply`

## 참고

- bootstrap 세부: [`infra/bootstrap/README.md`](infra/bootstrap/README.md)
- 매핑 샘플: [`mappings/dept_code.json`](mappings/dept_code.json)
