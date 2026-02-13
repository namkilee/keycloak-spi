# ---- 1) build stage: build spi-modules and collect providers ----
FROM maven:3.9.8-eclipse-temurin-17 AS builder
WORKDIR /workspace

# 캐시 효율: 우선 pom들만 복사
COPY pom.xml ./pom.xml
COPY spi-modules/pom.xml ./spi-modules/pom.xml

# (spi-modules가 다른 모듈들에 의존하면 -am 으로 가져오지만,
#  dependency:go-offline 정확도를 더 올리려면 해당 모듈 pom들도 추가 COPY 해도 됨)
RUN mvn -q -DskipTests -pl spi-modules -am dependency:go-offline

# 전체 소스 복사 후 패키징
COPY . .
RUN mvn -q -DskipTests -pl spi-modules -am package

# ---- 2) runtime stage: keycloak + providers/themes baked-in ----
FROM docker-remote.bart.sec.samsung.net/bitnamilegacy/keycloak:26.3.3-debian-12-r0

# SPI providers: spi-modules/target/providers 안의 jar들만 복사
COPY --from=builder /workspace/spi-modules/target/providers/ /opt/bitnami/keycloak/providers/

# themes 폴더도 bake-in (repo에 themes가 있다고 했으니)
COPY --from=builder /workspace/themes/ /opt/bitnami/keycloak/themes/

USER 0
RUN chown -R 1001:1001 /opt/bitnami/keycloak/providers /opt/bitnami/keycloak/themes || true
USER 1001
