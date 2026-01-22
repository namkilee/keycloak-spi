# syntax=docker/dockerfile:1

FROM maven:3.9.6-eclipse-temurin-17 AS builder
WORKDIR /workspace
COPY spi /workspace/spi
WORKDIR /workspace/spi
RUN mvn -q -pl terms-ra,claim-mappers -am package

FROM quay.io/keycloak/keycloak:24.0.5
USER root
RUN mkdir -p /opt/keycloak/providers /opt/keycloak/themes
COPY --from=builder /workspace/spi/terms-ra/target/*.jar /opt/keycloak/providers/
COPY --from=builder /workspace/spi/claim-mappers/target/*.jar /opt/keycloak/providers/
COPY deploy/themes /opt/keycloak/themes
RUN /opt/keycloak/bin/kc.sh build
USER 1000

ENTRYPOINT ["/opt/keycloak/bin/kc.sh"]
CMD ["start"]
