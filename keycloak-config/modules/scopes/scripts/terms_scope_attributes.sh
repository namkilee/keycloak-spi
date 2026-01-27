#!/usr/bin/env bash
set -euo pipefail

if [ -z "${KCADM_PATH:-}" ]; then
  echo "KCADM_PATH must be set" >&2
  exit 1
fi

case "${KCADM_EXEC_MODE}" in
  docker)
    if [ -z "${KEYCLOAK_CONTAINER_NAME:-}" ]; then
      echo "KEYCLOAK_CONTAINER_NAME is required when KCADM_EXEC_MODE=docker" >&2
      exit 1
    fi
    KCADM_BASE=(docker exec "${KEYCLOAK_CONTAINER_NAME}" "${KCADM_PATH}")
    ;;
  kubectl)
    if [ -z "${KEYCLOAK_NAMESPACE:-}" ] || [ -z "${KEYCLOAK_POD_SELECTOR:-}" ]; then
      echo "KEYCLOAK_NAMESPACE and KEYCLOAK_POD_SELECTOR are required when KCADM_EXEC_MODE=kubectl" >&2
      exit 1
    fi
    POD="$(kubectl -n "${KEYCLOAK_NAMESPACE}" get pod -l "${KEYCLOAK_POD_SELECTOR}" -o jsonpath='{.items[0].metadata.name}')"
    if [ -z "${POD}" ]; then
      echo "No Keycloak pod found for selector ${KEYCLOAK_POD_SELECTOR} in ${KEYCLOAK_NAMESPACE}" >&2
      exit 1
    fi
    KCADM_BASE=(kubectl -n "${KEYCLOAK_NAMESPACE}" exec "$POD" -- "${KCADM_PATH}")
    ;;
  *)
    echo "Unsupported KCADM_EXEC_MODE: ${KCADM_EXEC_MODE}" >&2
    exit 1
    ;;
esac

"${KCADM_BASE[@]}" config credentials \
  --server "${KEYCLOAK_URL}" \
  --realm "${KEYCLOAK_AUTH_REALM}" \
  --client "${KEYCLOAK_CLIENT_ID}" \
  --secret "${KEYCLOAK_CLIENT_SECRET}"

"${KCADM_BASE[@]}" update "client-scopes/${SCOPE_ID}" -r "${REALM_ID}" \
  -s "attributes.tc.required=${TC_REQUIRED}" \
  -s "attributes.tc.version=${TC_VERSION}" \
  ${TC_URL:+-s "attributes.tc.url=${TC_URL}"} \
  ${TC_TEMPLATE:+-s "attributes.tc.template=${TC_TEMPLATE}"} \
  ${TC_KEY:+-s "attributes.tc.key=${TC_KEY}"}
