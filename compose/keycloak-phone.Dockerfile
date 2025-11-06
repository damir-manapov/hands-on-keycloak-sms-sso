ARG PROVIDER_VERSION=21.0.2_phone-2.3.3
ARG KEYCLOAK_VERSION=21.0.2

FROM curlimages/curl:8.11.1 AS downloader

ARG PROVIDER_VERSION

WORKDIR /downloads

RUN curl -fL -o keycloak-phone-provider.jar \
        https://github.com/cooperlyt/keycloak-phone-provider/releases/download/${PROVIDER_VERSION}/keycloak-phone-provider.jar \
    && curl -fL -o keycloak-phone-provider.resources.jar \
        https://github.com/cooperlyt/keycloak-phone-provider/releases/download/${PROVIDER_VERSION}/keycloak-phone-provider.resources.jar \
    && curl -fL -o keycloak-sms-provider-dummy.jar \
        https://github.com/cooperlyt/keycloak-phone-provider/releases/download/${PROVIDER_VERSION}/keycloak-sms-provider-dummy.jar

FROM quay.io/keycloak/keycloak:${KEYCLOAK_VERSION}

USER root

RUN mkdir -p /opt/keycloak/providers

COPY --from=downloader /downloads/*.jar /opt/keycloak/providers/

RUN chown -R 1000:0 /opt/keycloak/providers

USER 1000

RUN /opt/keycloak/bin/kc.sh build
