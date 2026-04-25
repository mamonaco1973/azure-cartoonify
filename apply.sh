#!/bin/bash
set -euo pipefail

./check_env.sh


# ── Phase 1: Infrastructure (Cosmos DB + Functions + Web Storage + Entra App Reg)

echo "NOTE: Deploying infrastructure..."
cd 01-functions

# Pass Entra External ID config as Terraform variables.
export TF_VAR_entra_tenant_id="$ENTRA_TENANT_ID"
export TF_VAR_entra_tenant_name="$ENTRA_TENANT_NAME"
export TF_VAR_entra_sp_client_id="$ENTRA_SP_CLIENT_ID"
export TF_VAR_entra_sp_client_secret="$ENTRA_SP_CLIENT_SECRET"

terraform init -upgrade
terraform apply -auto-approve || true
terraform apply -auto-approve

RESOURCE_GROUP=$(terraform output -raw resource_group_name)
WEB_STORAGE_NAME=$(terraform output -raw web_storage_name)
WEB_BASE_URL=$(terraform output -raw web_base_url)
ENTRA_CLIENT_ID=$(terraform output -raw entra_client_id)
ENTRA_AUTHORITY=$(terraform output -raw entra_authority)

cd ..


# ── Phase 1.5: Associate app with Entra user flow via Graph API ───────────────

echo "NOTE: Associating notes-entra-app with user flow '${ENTRA_USER_FLOW_NAME}'..."

# The ARM SP has no Graph permissions in the External tenant — acquire a
# separate token using the Entra-scoped SP.
GRAPH_TOKEN=$(curl -s -X POST \
  "https://login.microsoftonline.com/${ENTRA_TENANT_ID}/oauth2/v2.0/token" \
  --data-urlencode "grant_type=client_credentials" \
  --data-urlencode "client_id=${ENTRA_SP_CLIENT_ID}" \
  --data-urlencode "client_secret=${ENTRA_SP_CLIENT_SECRET}" \
  --data-urlencode "scope=https://graph.microsoft.com/.default" \
  | jq -r '.access_token')

if [[ -z "$GRAPH_TOKEN" || "$GRAPH_TOKEN" == "null" ]]; then
  echo "ERROR: Failed to acquire Graph API token for user flow association."
  exit 1
fi

# Find the user flow ID by display name.
FLOW_ID=$(curl -s -G \
  --data-urlencode "\$filter=displayName eq '${ENTRA_USER_FLOW_NAME}'" \
  "https://graph.microsoft.com/v1.0/identity/authenticationEventsFlows" \
  -H "Authorization: Bearer ${GRAPH_TOKEN}" \
  | jq -r '.value[0].id')

if [[ -z "$FLOW_ID" || "$FLOW_ID" == "null" ]]; then
  echo "ERROR: User flow '${ENTRA_USER_FLOW_NAME}' not found in tenant."
  exit 1
fi

# Skip if already linked — makes apply.sh idempotent.
ALREADY_LINKED=$(curl -s \
  "https://graph.microsoft.com/v1.0/identity/authenticationEventsFlows/${FLOW_ID}/conditions/applications/includeApplications" \
  -H "Authorization: Bearer ${GRAPH_TOKEN}" \
  | jq -r --arg id "${ENTRA_CLIENT_ID}" '.value[] | select(.appId == $id) | .appId')

if [[ -n "$ALREADY_LINKED" ]]; then
  echo "NOTE: App already associated with user flow '${ENTRA_USER_FLOW_NAME}'."
else
  HTTP_STATUS=$(curl -s -o /dev/null -w "%{http_code}" -X POST \
    "https://graph.microsoft.com/v1.0/identity/authenticationEventsFlows/${FLOW_ID}/conditions/applications/includeApplications" \
    -H "Authorization: Bearer ${GRAPH_TOKEN}" \
    -H "Content-Type: application/json" \
    -d "{\"@odata.type\": \"#microsoft.graph.authenticationConditionApplication\", \"appId\": \"${ENTRA_CLIENT_ID}\"}")

  if [[ "$HTTP_STATUS" == "201" ]]; then
    echo "NOTE: App associated with user flow '${ENTRA_USER_FLOW_NAME}'."
  else
    echo "ERROR: Failed to associate app with user flow (HTTP ${HTTP_STATUS})."
    exit 1
  fi
fi


# ── Phase 2: Deploy function code ─────────────────────────────────────────────

echo "NOTE: Packaging and deploying function code..."
cd 01-functions/code

rm -f app.zip
zip -r app.zip . \
  -x "*.git*" \
  -x "*__pycache__*" \
  -x "*.pytest_cache*" \
  -x "*.DS_Store"

FUNC_APP_NAME=$(az functionapp list \
  --resource-group "$RESOURCE_GROUP" \
  --query "[?starts_with(name, 'notes-entra-func-')].name" \
  --output tsv)

az functionapp deployment source config-zip \
  --name "$FUNC_APP_NAME" \
  --resource-group "$RESOURCE_GROUP" \
  --src app.zip \
  --build-remote true

cd ../..

API_BASE="https://$(az functionapp show \
  --name "$FUNC_APP_NAME" \
  --resource-group "$RESOURCE_GROUP" \
  --query "properties.defaultHostName" \
  -o tsv)/api"

echo "NOTE: Function app: ${FUNC_APP_NAME}"
echo "NOTE: API base:     ${API_BASE}"


# ── Phase 3: Build web app config ─────────────────────────────────────────────

echo "NOTE: Building web app config..."

REDIRECT_URI="${WEB_BASE_URL}callback.html"

cat > 02-webapp/config.json <<EOF
{
  "authority":   "${ENTRA_AUTHORITY}",
  "clientId":    "${ENTRA_CLIENT_ID}",
  "redirectUri": "${REDIRECT_URI}",
  "apiBaseUrl":  "${API_BASE}"
}
EOF

# index.html.tmpl has no placeholders — copy as-is.
cp 02-webapp/index.html.tmpl 02-webapp/index.html


# ── Phase 4: Deploy web app ────────────────────────────────────────────────────

echo "NOTE: Deploying web app..."
cd 02-webapp
terraform init -upgrade
terraform apply -auto-approve -var="web_storage_name=${WEB_STORAGE_NAME}"

WEBSITE_URL=$(terraform output -raw website_url)
cd ..

echo ""
echo "NOTE: Deployment complete."
echo "NOTE: API:     ${API_BASE}"
echo "NOTE: Web app: ${WEBSITE_URL}index.html"
echo ""

./validate.sh
