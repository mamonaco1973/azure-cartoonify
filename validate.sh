#!/bin/bash
set -euo pipefail

# ================================================================================
# File: validate.sh
# ================================================================================

# ------------------------------------------------------------------------------
# Step 1: Read web app URL from Terraform outputs (02-webapp)
# ------------------------------------------------------------------------------

cd 02-webapp
WEBSITE_URL=$(terraform output -raw website_url 2>/dev/null || true)
cd ..

if [[ -z "${WEBSITE_URL}" ]]; then
  echo "ERROR: Could not read Terraform output 'website_url' from 02-webapp."
  echo "       Run './apply.sh' first."
  exit 1
fi

# ------------------------------------------------------------------------------
# Step 2: Read function app URL from Terraform outputs (01-functions)
# ------------------------------------------------------------------------------

cd 01-functions
FUNC_APP_URL=$(terraform output -raw function_app_url 2>/dev/null || true)
cd ..

if [[ -z "${FUNC_APP_URL}" ]]; then
  echo "ERROR: Could not read Terraform output 'function_app_url' from 01-functions."
  echo "       Run './apply.sh' first."
  exit 1
fi

echo ""
echo "================================================================================="
echo "  Deployment validated!"
echo "================================================================================="
echo "  API : ${FUNC_APP_URL}"
echo "  Web : ${WEBSITE_URL}index.html"
echo "================================================================================="
echo ""
