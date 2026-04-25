# Azure Serverless Notes API with Azure Functions, Cosmos DB, and Microsoft Entra External ID

This project delivers a fully automated **serverless CRUD API** on Azure, secured
with **Microsoft Entra External ID** authentication. It uses **Azure Functions**,
**Azure Cosmos DB**, and **Azure Blob Storage**, provisioned entirely with **Terraform**
and deployed with shell scripts — no virtual machines, no manual portal configuration
beyond the one-time Entra External tenant setup.

For testing and demonstration purposes, a lightweight **HTML web frontend**
interacts directly with the deployed API, allowing signed-in users to create, view,
update, and delete their own notes from a browser.

![webapp](webapp.png)

This design follows a **serverless microservice architecture** where Azure Functions
handle HTTP routing and JWT validation, Cosmos DB provides fully managed NoSQL
persistence scoped per authenticated user, and Blob Storage hosts the static
frontend.

Key capabilities demonstrated:

1. **Authenticated CRUD API** — All five REST endpoints require a valid Entra External
   ID access token. The function code validates the JWT signature against the Entra
   JWKS endpoint and rejects unsigned or expired tokens with HTTP 401.
2. **Per-User Data Isolation** — The Cosmos DB partition key `/owner` is set from
   the JWT `sub` claim. Each user can only read and write their own notes — enforced
   at the storage layer, not just the application layer.
3. **PKCE OAuth2 Flow** — The SPA uses the Authorization Code + PKCE flow with no
   client secret. `callback.html` exchanges the authorization code for tokens and
   stores them in `sessionStorage`.
4. **Stateless Compute Layer** — All five operations are handled by a single
   Function App on a Flex Consumption plan — zero idle cost, scales on demand.
5. **Infrastructure as Code (IaC)** — Terraform provisions the Function App, Cosmos
   DB, Blob Storage, and Entra app registration in a repeatable, auditable way.

---

## Authentication Flow

![diagram](azure-entra-app.png)

```
1. User clicks "Sign In" in the browser
2. SPA generates PKCE verifier + challenge, stores verifier in sessionStorage
3. Browser redirects to Entra External ID hosted sign-in UI (authorize endpoint)
4. User creates an account or signs in with email + password
5. Entra redirects to callback.html?code=...&state=...
6. callback.html validates state, exchanges code + verifier for tokens
7. access_token, id_token, refresh_token stored in sessionStorage
8. Browser redirects to index.html
9. All API calls include Authorization: Bearer <access_token>
10. Function validates JWT signature via Entra JWKS, extracts sub as owner
11. Cosmos DB queries are scoped to the owner partition key
```

---

## Prerequisites

### Tools

* [An Azure Account](https://portal.azure.com/)
* [Azure CLI](https://docs.microsoft.com/en-us/cli/azure/install-azure-cli)
* [Terraform](https://developer.hashicorp.com/terraform/install)
* [jq](https://jqlang.github.io/jq/download/)

### One-time Entra External ID setup (Azure Portal)

The External tenant and user flow must be created manually before the first deploy.
Everything else is automated.

**1. Create a Microsoft Entra External ID tenant**

In the Azure Portal, go to **Microsoft Entra ID → Overview → Manage tenants → New**.
Select **External** as the tenant type. Choose a subdomain name — this becomes
`ENTRA_TENANT_NAME` (e.g. `mynotesapp` from `mynotesapp.onmicrosoft.com`). Note the
**tenant ID (GUID)** from the tenant overview — this is `ENTRA_TENANT_ID`.

**2. Create a sign-up/sign-in user flow**

Switch your portal directory to the External tenant. Go to **Microsoft Entra ID →
External Identities → User flows → New user flow**. Select **Sign up and sign in**.
Under **Identity providers**, select **Email with password**. Under **User attributes**,
collect and return **Email Address**. Click **Create**.

**3. Create a service principal in the Entra External tenant**

Still in the External tenant, go to **App registrations → New registration**. After
creation, go to **Certificates & secrets** and add a client secret. Go to **API
permissions → Add a permission → Microsoft Graph → Application permissions**, add
`Application.ReadWrite.All` and `EventListener.ReadWrite.All`, then click
**Grant admin consent**. Note the **Application (client) ID**
(`ENTRA_SP_CLIENT_ID`) and the secret (`ENTRA_SP_CLIENT_SECRET`).

### Required environment variables

```bash
# Azure subscription
export ARM_CLIENT_ID="..."
export ARM_CLIENT_SECRET="..."
export ARM_SUBSCRIPTION_ID="..."
export ARM_TENANT_ID="..."

# Microsoft Entra External ID
export ENTRA_TENANT_ID="..."           # GUID of the External tenant
export ENTRA_TENANT_NAME="mynotesapp"  # Domain prefix only (no .onmicrosoft.com)
export ENTRA_SP_CLIENT_ID="..."        # Service principal registered IN the External tenant
export ENTRA_SP_CLIENT_SECRET="..."
export ENTRA_USER_FLOW_NAME="..."      # Display name of the sign-up/sign-in user flow
```

---

## Download this Repository

```bash
git clone https://github.com/mamonaco1973/azure-entra-app.git
cd azure-entra-app
```

## Build the Code

Run [check_env.sh](check_env.sh) to validate your environment, then run
[apply.sh](apply.sh) to provision all infrastructure and deploy the application.

```bash
~/azure-entra-app$ ./apply.sh
NOTE: All required commands are available.
NOTE: All required environment variables are set.
NOTE: Successfully logged into Azure.
NOTE: Deploying infrastructure...

Initializing the backend...
```

`apply.sh` performs the following steps in order:

1. Runs `check_env.sh` — validates CLI tools, env vars, and Azure authentication
2. Deploys `01-functions` — resource group, Cosmos DB, Function App, Blob Storage
   web account, and Entra app registration (with redirect URI pointed at the storage URL)
3. Packages and deploys the Python function code via `az functionapp deployment source config-zip`
4. Generates `02-webapp/config.json` with the Entra authority, client ID, redirect URI,
   and API base URL
5. Copies `index.html.tmpl` → `index.html`
6. Deploys `02-webapp` — uploads `index.html`, `callback.html`, `config.json`, and
   `favicon.ico` to the `$web` container
7. Runs `validate.sh` to print the web app URL

To tear down all resources:

```bash
./destroy.sh
```

---

## Build Results

When the deployment completes, the following resources are created in a single
resource group `notes-entra-rg`:

- **Azure Cosmos DB:**
  - Account with Session consistency and GlobalDocumentDB kind
  - Database `notes` with container `notes`
  - Partition key `/owner` — set to the authenticated user's `sub` claim
  - Item ID is a UUID

- **Azure Functions:**
  - Flex Consumption plan (`FC1`) — serverless, pay-per-execution
  - Python 3.11 runtime with Python v2 programming model
  - Single `function_app.py` implementing all five routes
  - CORS restricted to the Blob Storage origin
  - Entra tenant name, tenant ID, and client ID injected via app settings
  - JWT validation (`PyJWT` + `cryptography`) performed in function code

- **Static Web App (Blob Storage):**
  - Storage account `notesentraweb<suffix>` with static website hosting
  - `index.html`, `callback.html`, `config.json`, and `favicon.ico` in the `$web` container
  - PKCE OAuth2 flow — no client secret exposed in the browser
  - Tokens stored in `sessionStorage`

- **Microsoft Entra External ID:**
  - App registration `notes-entra-app` (SPA platform, no client secret)
  - Redirect URI: `https://<storage>.z1.web.core.windows.net/callback.html`
  - Managed by Terraform via the `azuread` provider pointed at the External tenant

---

## API Endpoints

All endpoints require `Authorization: Bearer <access_token>` and return JSON.

| Method | Path | Purpose | Input | Cosmos DB Operation |
|---|---|---|---|---|
| POST | `/api/notes` | Create a new note | JSON body (`title`, `note`) | `create_item` |
| GET | `/api/notes` | List caller's notes | None (owner from JWT) | `query_items` |
| GET | `/api/notes/{id}` | Get a single note | Path param (`id`) | `read_item` |
| PUT | `/api/notes/{id}` | Update a note | Path param + JSON body | `replace_item` |
| DELETE | `/api/notes/{id}` | Delete a note | Path param (`id`) | `delete_item` |

| Aspect | Behavior |
|---|---|
| Authentication | Entra External ID JWT (Bearer token, RS256) |
| Authorization | Owner scoped — callers can only access their own notes |
| Content-Type | `application/json` |
| Unauthenticated | HTTP 401 |
| Not found / wrong owner | HTTP 404 |

### POST /api/notes

**Request:**
```bash
curl -s -X POST https://<func-app>.azurewebsites.net/api/notes \
  -H "Authorization: Bearer <access_token>" \
  -H "Content-Type: application/json" \
  -d '{"title":"Test Note","note":"This is my note"}'
```

**Response (201):**
```json
{
  "id": "2f2d0c5a-9f5f-4d7d-9e2c-1c8a5b8e3c21",
  "title": "Test Note",
  "note": "This is my note"
}
```

### GET /api/notes

**Response (200):**
```json
{
  "items": [
    {
      "id": "2f2d0c5a-9f5f-4d7d-9e2c-1c8a5b8e3c21",
      "title": "Test Note",
      "note": "This is my note",
      "created_at": "2026-04-10T14:12:09.123456+00:00",
      "updated_at": "2026-04-10T14:12:09.123456+00:00"
    }
  ]
}
```

### GET /api/notes/{id}

```bash
curl -s https://<func-app>.azurewebsites.net/api/notes/<id> \
  -H "Authorization: Bearer <access_token>"
```

### PUT /api/notes/{id}

```bash
curl -s -X PUT https://<func-app>.azurewebsites.net/api/notes/<id> \
  -H "Authorization: Bearer <access_token>" \
  -H "Content-Type: application/json" \
  -d '{"title":"Updated Title","note":"Updated content"}'
```

### DELETE /api/notes/{id}

```bash
curl -s -X DELETE https://<func-app>.azurewebsites.net/api/notes/<id> \
  -H "Authorization: Bearer <access_token>"
```

---

## Project Structure

```
azure-entra-app/
├── 01-functions/
│   ├── code/
│   │   ├── function_app.py    # 5 Azure Functions; JWT validated in validate_token()
│   │   ├── requirements.txt   # azure-functions, azure-cosmos, PyJWT, cryptography, requests
│   │   └── host.json          # Extension bundle v4
│   ├── entra.tf               # azuread_application (SPA, PKCE, redirect URI)
│   ├── cosmosdb.tf            # Cosmos DB account, database, container (/owner partition)
│   ├── functions.tf           # Storage, service plan, Function App + Entra env vars
│   ├── main.tf                # azurerm + azuread providers, resource group, random suffix
│   ├── outputs.tf             # URLs, storage name, Entra client ID + authority
│   ├── storage.tf             # Web hosting storage account (here so URL is known for Entra redirect URI)
│   └── variables.tf           # location + Entra variables
├── 02-webapp/
│   ├── callback.html          # PKCE auth code exchange; stores tokens in sessionStorage
│   ├── config.json            # Generated at deploy time — not committed
│   ├── favicon.ico            # Site icon
│   ├── index.html.tmpl        # SPA with auth gate, PKCE sign-in/out, JWT in all API calls
│   ├── main.tf                # azurerm provider + web_storage_name variable
│   └── storage.tf             # Blob uploads only (index.html, callback.html, config.json, favicon.ico)
├── apply.sh                   # Full deployment orchestrator (4 phases)
├── destroy.sh                 # Reverse teardown
├── validate.sh                # Prints web app URL
└── check_env.sh               # Validates tools, Entra env vars, and Azure auth
```
