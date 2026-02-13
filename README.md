# Keycloak SPI Extensions + Terraform Config

이 저장소는 Keycloak 확장을 위한 **SPI 모듈(Java/Maven)** 과 운영 구성을 위한 **Terraform 코드**를 함께 관리한다.

## 구성

- `spi-modules/`: Keycloak SPI 멀티 모듈 Maven 프로젝트
- `keycloak-config/`: Realm/Client/Scope/IdP/Required Action/Realm Attribute Terraform 구성
- `deploy/`: 배포 관련 레거시/샘플 리소스(도커/헬름/테마)

## SPI 모듈

`spi-modules/pom.xml` 기준으로 현재 활성 모듈은 아래 4개다.

1. `terms-action`
   - Required Action provider id: `terms-required-action`
   - 클라이언트에 연결된 스코프의 `tc.<termKey>.*` 속성을 병합해 약관 UI를 렌더링
   - 수락 결과는 사용자 attribute `tc.accepted.<clientId>.<termKey>`에 저장
2. `claim-mappers`
   - Protocol mapper id: `value-transform-protocol-mapper`
   - 사용자 attribute 값을 규칙에 따라 토큰 claim으로 변환
   - mapping source: client attribute / file(URL) / DB / API / inline
3. `userinfo-sync`
   - 스케줄 기반 사용자 속성 동기화 provider
   - Realm attribute(`userinfosync.*`) + Knox API 환경변수(`KNOX_*`)로 동작
4. `access-approval-action`
   - Authenticator id: `approval-gate-authenticator`
   - client attribute `auto_approve`, role `approved`, `approval_portal_url`을 기반으로 승인 게이트 처리

## 빠른 빌드

```bash
mvn -f spi-modules/pom.xml -pl terms-action,claim-mappers,userinfo-sync,access-approval-action -am package
```

빌드된 jar는 각 모듈 `target/`과 루트 `spi-modules/target/providers/`(일부 모듈의 antrun 복사 설정)에서 확인할 수 있다.

## Terraform 연계 포인트

- `keycloak-config/modules/realm-clients`에서:
  - Required Action `terms-required-action` 등록
  - 각 서비스 클라이언트에 `approved` client role 생성
  - 승인 포털(`approval-portal`) 클라이언트/권한 구성
  - Post Broker Login Flow에 `approval-gate-authenticator` 실행 연결
- `keycloak-config/modules/scopes`에서:
  - 클라이언트/공유 스코프와 protocol mapper 생성
  - `tc_sets`를 `kcadm` 스크립트로 `tc.<termKey>.*` attribute로 동기화

## 참고 문서

- SPI 상세: [`spi-modules/README.md`](spi-modules/README.md)
- Terraform 상세: [`keycloak-config/README.md`](keycloak-config/README.md)
- Bootstrap 루트 상세: [`keycloak-config/infra/bootstrap/README.md`](keycloak-config/infra/bootstrap/README.md)
- 배포 리소스 상세: [`deploy/README.md`](deploy/README.md)
