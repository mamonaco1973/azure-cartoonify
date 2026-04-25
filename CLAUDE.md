# azure-cartoonify

Serverless image-to-cartoon service on Azure. Users sign in via Entra External
ID, upload a photo, pick a style, and an Azure Service Bus–driven worker calls
Azure OpenAI gpt-image-1 to generate a cartoon. Results are stored in Blob
Storage for 7 days and accessed via short-lived SAS URLs.

## Architecture

```
Browser → Blob Storage SPA → Entra External ID (PKCE) → sessionStorage (JWT)

Browser → POST /api/upload-url → Function App (JWT) → Blob SAS URL
Browser → PUT (direct) ──────→ Blob Storage media (originals/<owner>/<job_id>.<ext>)

Browser → POST /api/generate → Function App (JWT) → Cosmos DB (status=submitted)
                                                  → Service Bus cartoonify-jobs
                                                          ↓
                               Service Bus trigger (cartoonify_worker)
                               • Pillow: EXIF strip, 1024×1024 crop/resize
                               • Azure OpenAI gpt-image-1 images.edit
                               • Blob upload cartoons/<owner>/<job_id>.png
                               • Cosmos DB (status=complete)

Browser → GET /api/result/{job_id} → SAS download URLs
Browser → GET /api/history         → newest 50 for owner
Browser → DELETE /api/history/{id} → delete blobs + Cosmos row
```

**Azure services:** Azure Functions (FC1 Flex Consumption), Service Bus (Standard),
Cosmos DB (SQL API), Blob Storage (web SPA + media), Microsoft Entra External ID.

**Image generation:** OpenAI API (api.openai.com) — gpt-image-1 images.edit,
authenticated via OPENAI_API_KEY stored as a Function App setting. Azure OpenAI
is not used; gpt-image-1 requires subscription allowlisting on Azure which is
not generally available.

## Prerequisites

The following must exist **before** running `apply.sh`. Everything else is automated.

| Prerequisite | Notes |
|---|---|
| Entra External tenant | Created in Azure Portal; provides `ENTRA_TENANT_ID` and `ENTRA_TENANT_NAME` |
| Sign-up/sign-in user flow | Created in the External tenant; email + password identity provider |
| Service principal in External tenant | Needs `Application.ReadWrite.All` on Microsoft Graph |

## Required Environment Variables

```bash
ARM_CLIENT_ID
ARM_CLIENT_SECRET
ARM_SUBSCRIPTION_ID
ARM_TENANT_ID
ENTRA_TENANT_ID
ENTRA_TENANT_NAME
ENTRA_SP_CLIENT_ID
ENTRA_SP_CLIENT_SECRET
ENTRA_USER_FLOW_NAME
OPENAI_API_KEY
```

## Deploy / Destroy

```bash
./apply.sh      # 3-stage deploy: backend → functions → webapp
./destroy.sh    # Reverse teardown
./validate.sh   # Print API + web URLs
```

## Project Structure

```
azure-cartoonify/
├── 01-backend/          SB, Cosmos DB, Blob Storage (web+media), Azure OpenAI, Entra app
├── 02-functions/        Function App Terraform + code deploy
│   └── code/
│       ├── function_app.py   5 HTTP routes + SB queue trigger worker
│       ├── common.py         shared helpers
│       ├── requirements.txt
│       └── host.json
├── 03-webapp/           SPA: index.html.tmpl, callback.html, favicon.ico
├── apply.sh
├── destroy.sh
├── validate.sh
└── check_env.sh
```

## Key Design Decisions

**3-stage Terraform split** — 01-backend provisions all stateful infrastructure
(including web storage whose URL must be known before the Entra redirect URI is
written). 02-functions provisions compute and RBAC, referencing 01-backend
outputs as variables. 03-webapp uploads SPA assets.

**JWT in code, not Easy Auth** — each HTTP route calls `validate_token(req)`;
JWKS is cached per warm instance. The JWT `sub` claim is the Cosmos DB partition
key, enforcing per-user data isolation at the storage layer.

**Azure OpenAI managed identity** — the Function App calls gpt-image-1 via
`get_bearer_token_provider` (no API key in app settings); access is granted
via `Cognitive Services OpenAI User` role assignment.

**Blob SAS for upload/download** — replaces S3 presigned POST/GET. Upload uses
`BlobSasPermissions(create=True, write=True)` with a 5-min expiry; download uses
`BlobSasPermissions(read=True)` with a 4-hour expiry. Account key is stored as
a Function App setting for SAS signing.

## Key Resources

| Resource | Name pattern |
|---|---|
| Resource group | `cartoonify-rg` |
| Location | `Central US` |
| Function App | `cartoonify-func-<hex>` |
| Service Bus namespace | `sb-cartoonify-<hex>` |
| Service Bus queue | `cartoonify-jobs` |
| Cosmos DB account | `cosmos-cartoonify-<hex>` |
| Cosmos DB container | `jobs`, partition key `/owner` |
| Media storage | `cartoonmedia<hex>` |
| Web storage | `cartoonweb<hex>` |
| Azure OpenAI | `cartoonify-openai-<random>` |
| Entra app registration | `cartoonify-app` |
