#!/bin/bash
set -euo pipefail

# ================================================================================
# File: validate.sh
# ================================================================================

cd 03-webapp
WEBSITE_URL=$(terraform output -raw website_url 2>/dev/null || true)
cd ..

if [[ -z "${WEBSITE_URL}" ]]; then
  echo "ERROR: Could not read Terraform output 'website_url' from 03-webapp."
  echo "       Run './apply.sh' first."
  exit 1
fi

cd 02-functions
FUNC_APP_URL=$(terraform output -raw function_app_url 2>/dev/null || true)
cd ..

if [[ -z "${FUNC_APP_URL}" ]]; then
  echo "ERROR: Could not read Terraform output 'function_app_url' from 02-functions."
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
