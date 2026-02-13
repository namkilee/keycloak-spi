# SPI Modules

이 디렉터리는 Keycloak SPI 멀티 모듈 Maven 프로젝트다.

## 모듈 목록

- `terms-action`
  - `RequiredActionFactory` 등록 파일:
    `META-INF/services/org.keycloak.authentication.RequiredActionFactory`
  - provider id: `terms-required-action`
- `claim-mappers`
  - `ProtocolMapper` 등록 파일:
    `META-INF/services/org.keycloak.protocol.ProtocolMapper`
  - provider id: `value-transform-protocol-mapper`
- `userinfo-sync`
  - `ProviderFactory` 등록 파일:
    `META-INF/services/org.keycloak.provider.ProviderFactory`
- `access-approval-action`
  - `AuthenticatorFactory` 등록 파일:
    `META-INF/services/org.keycloak.authentication.AuthenticatorFactory`
  - provider id: `approval-gate-authenticator`

## 빌드

```bash
mvn -f spi-modules/pom.xml package
```

특정 모듈만 빌드:

```bash
mvn -f spi-modules/pom.xml -pl terms-action,claim-mappers,userinfo-sync,access-approval-action -am package
```

## 버전/런타임 기준

- Java 17
- Keycloak SPI API 26.3.3

값은 `spi-modules/pom.xml`의 `java.version`, `keycloak.version`을 기준으로 맞춘다.
