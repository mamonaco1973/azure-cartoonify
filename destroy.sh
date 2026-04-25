#!/bin/bash
set -euo pipefail

./check_env.sh

# Read outputs before state is destroyed.
cd 01-backend
WEB_STORAGE_NAME=$(terraform output -raw web_storage_name 2>/dev/null || true)
ENTRA_CLIENT_ID=$(terraform output -raw entra_client_id 2>/dev/null || true)
cd ..

# ── Destroy web app first (depends on web storage from 01-backend) ────────────

echo "NOTE: Destroying web app..."
cd 03-webapp
terraform init -upgrade
terraform destroy -auto-approve -var="web_storage_name=${WEB_STORAGE_NAME:-placeholder}"
cd ..


# ── Destroy Function App ───────────────────────────────────────────────────────

echo "NOTE: Destroying Function App..."
cd 02-functions
terraform init -upgrade
terraform destroy -auto-approve \
  -var="resource_group_name=cartoonify-rg" \
  -var="servicebus_namespace_fqdn=placeholder" \
  -var="servicebus_queue_name=placeholder" \
  -var="servicebus_queue_id=placeholder" \
  -var="cosmos_endpoint=placeholder" \
  -var="cosmos_account_name=placeholder" \
  -var="cosmos_role_definition_id=placeholder" \
  -var="media_storage_name=placeholder" \
  -var="media_storage_key=placeholder" \
  -var="media_blob_endpoint=placeholder" \
  -var="openai_endpoint=placeholder" \
  -var="openai_account_id=placeholder" \
  -var="openai_deployment_name=placeholder" \
  -var="entra_tenant_name=placeholder" \
  -var="entra_tenant_id=placeholder" \
  -var="entra_client_id=placeholder" \
  -var="web_origin=placeholder"
cd ..


# ── Phase 1.5 cleanup: remove app from Entra user flow ────────────────────────

echo "NOTE: Removing cartoonify-app from user flow '${ENTRA_USER_FLOW_NAME}'..."

(
  if [[ -z "$ENTRA_CLIENT_ID" ]]; then
    echo "NOTE: No Entra client ID in state. Skipping association cleanup."
    exit 0
  fi

  GRAPH_TOKEN=$(curl -s -X POST \
    "https://login.microsoftonline.com/${ENTRA_TENANT_ID}/oauth2/v2.0/token" \
    --data-urlencode "grant_type=client_credentials" \
    --data-urlencode "client_id=${ENTRA_SP_CLIENT_ID}" \
    --data-urlencode "client_secret=${ENTRA_SP_CLIENT_SECRET}" \
    --data-urlencode "scope=https://graph.microsoft.com/.default" \
    | jq -r '.access_token')

  if [[ -z "$GRAPH_TOKEN" || "$GRAPH_TOKEN" == "null" ]]; then
    echo "WARNING: Could not acquire Graph token. Skipping association cleanup."
    exit 0
  fi

  FLOW_ID=$(curl -s -G \
    --data-urlencode "\$filter=displayName eq '${ENTRA_USER_FLOW_NAME}'" \
    "https://graph.microsoft.com/v1.0/identity/authenticationEventsFlows" \
    -H "Authorization: Bearer ${GRAPH_TOKEN}" \
    | jq -r '.value[0].id')

  if [[ -z "$FLOW_ID" || "$FLOW_ID" == "null" ]]; then
    echo "WARNING: User flow '${ENTRA_USER_FLOW_NAME}' not found. Skipping."
    exit 0
  fi

  HTTP_STATUS=$(curl -s -o /dev/null -w "%{http_code}" -X DELETE \
    "https://graph.microsoft.com/v1.0/identity/authenticationEventsFlows/${FLOW_ID}/conditions/applications/includeApplications/${ENTRA_CLIENT_ID}" \
    -H "Authorization: Bearer ${GRAPH_TOKEN}")

  if [[ "$HTTP_STATUS" == "204" ]]; then
    echo "NOTE: App removed from user flow."
  elif [[ "$HTTP_STATUS" == "404" ]]; then
    echo "NOTE: App was not associated with user flow (already clean)."
  else
    echo "WARNING: Unexpected HTTP ${HTTP_STATUS} removing app from user flow."
    exit 1
  fi
) || echo "WARNING: Phase 1.5 cleanup failed. Continuing with destroy..."


# ── Destroy backend infrastructure ────────────────────────────────────────────

echo "NOTE: Destroying backend infrastructure..."

export TF_VAR_entra_tenant_id="$ENTRA_TENANT_ID"
export TF_VAR_entra_tenant_name="$ENTRA_TENANT_NAME"
export TF_VAR_entra_sp_client_id="$ENTRA_SP_CLIENT_ID"
export TF_VAR_entra_sp_client_secret="$ENTRA_SP_CLIENT_SECRET"

cd 01-backend
terraform init -upgrade
terraform destroy -auto-approve
cd ..

echo "NOTE: Teardown complete."
