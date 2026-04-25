import azure.functions as func
import json
import uuid
import os
import requests
from datetime import datetime, timezone
from azure.cosmos import CosmosClient, exceptions
import jwt
from jwt.algorithms import RSAAlgorithm

# ================================================================================
# Configuration
# Auth is enforced in code rather than by the platform so the JWT sub claim can
# be extracted and used as the Cosmos DB partition key (owner).
# ================================================================================

app = func.FunctionApp(http_auth_level=func.AuthLevel.ANONYMOUS)

# Cosmos DB connection — injected by Terraform via Function App settings
ENDPOINT    = os.environ["COSMOS_ENDPOINT"]
KEY         = os.environ["COSMOS_KEY"]
DATABASE    = os.environ["COSMOS_DATABASE"]
CONTAINER   = os.environ["COSMOS_CONTAINER"]

# Entra External ID config — used to build the JWKS discovery URL and to
# validate the audience claim on incoming tokens
ENTRA_TENANT    = os.environ["ENTRA_TENANT_NAME"]
ENTRA_TENANT_ID = os.environ["ENTRA_TENANT_ID"]
CLIENT_ID       = os.environ["ENTRA_CLIENT_ID"]

# Cached per function-app instance (warm invocations skip the JWKS fetch).
_jwks_cache = None


# ================================================================================
# Auth Helpers
# JWT validation against Entra External ID's public key set. The owner ID
# extracted here becomes the Cosmos DB partition key, enforcing per-user
# data isolation at the storage layer.
# ================================================================================

def _get_jwks():
    """Fetch the Entra External ID public key set, cached per instance.

    Entra External ID uses ciamlogin.com (not login.microsoftonline.com) —
    no policy name suffix is needed in the discovery URL. Caching avoids a
    network round-trip on warm invocations; the cache lives for the lifetime
    of the instance.

    Returns:
        A dict containing the JWKS key set from the Entra discovery endpoint.
    """
    global _jwks_cache
    if _jwks_cache is None:
        url = (
            f"https://{ENTRA_TENANT}.ciamlogin.com/{ENTRA_TENANT_ID}"
            f"/discovery/v2.0/keys"
        )
        _jwks_cache = requests.get(url, timeout=5).json()
    return _jwks_cache


def validate_token(req: func.HttpRequest):
    """Return the owner ID (sub claim) if the Bearer token is valid, else None.

    Validates the RS256 signature against the Entra JWKS, then checks that
    the audience matches the registered client ID. Returns sub (preferred)
    or oid as the owner, which becomes the Cosmos DB partition key for all
    subsequent queries.

    Args:
        req: The incoming Azure Functions HTTP request.

    Returns:
        A string owner ID if the token is valid, or None if missing/invalid.
    """
    auth = req.headers.get("Authorization", "")
    if not auth.startswith("Bearer "):
        return None
    token = auth[7:]
    try:
        jwks = _get_jwks()
        header = jwt.get_unverified_header(token)
        # Match the signing key by kid — Entra rotates keys periodically
        key_data = next((k for k in jwks["keys"] if k["kid"] == header["kid"]), None)
        if key_data is None:
            return None
        public_key = RSAAlgorithm.from_jwk(json.dumps(key_data))
        claims = jwt.decode(
            token,
            public_key,
            algorithms=["RS256"],
            audience=CLIENT_ID,
        )
        # sub is the stable per-user identifier in CIAM tokens; oid is the
        # fallback for token configurations that omit sub (uncommon)
        return claims.get("sub") or claims.get("oid")
    except Exception:
        return None


# ================================================================================
# Cosmos DB / Response Helpers
# ================================================================================

def get_container():
    """Return a Cosmos DB container client for the notes container.

    Creates a new CosmosClient on each call — the SDK manages HTTP connection
    pooling internally, so this is safe for serverless invocations without
    requiring module-level connection state.

    Returns:
        A ContainerProxy for the configured notes container.
    """
    client = CosmosClient(ENDPOINT, KEY)
    return client.get_database_client(DATABASE).get_container_client(CONTAINER)


def resp(status, body):
    """Serialize body as JSON and return an HttpResponse with the given status.

    Args:
        status: HTTP status code integer.
        body: JSON-serializable dict to include as the response body.

    Returns:
        An HttpResponse with application/json content type.
    """
    return func.HttpResponse(
        json.dumps(body),
        status_code=status,
        mimetype="application/json",
        headers={"Content-Type": "application/json"},
    )


# ================================================================================
# CRUD Endpoints
# All routes require a valid Bearer token. The owner is extracted from the JWT
# sub claim and used as the Cosmos DB partition key — queries never cross
# partition boundaries, so one user cannot read or modify another user's notes.
# ================================================================================

# ── POST /api/notes ────────────────────────────────────────────────────────────

@app.route(route="notes", methods=["POST"])
def create_note(req: func.HttpRequest) -> func.HttpResponse:
    owner = validate_token(req)
    if not owner:
        return resp(401, {"error": "Unauthorized"})

    try:
        body = req.get_json()
    except ValueError:
        return resp(400, {"error": "Invalid JSON"})

    title = body.get("title", "").strip()
    note  = body.get("note",  "").strip()
    if not title:
        return resp(400, {"error": "title is required"})

    now  = datetime.now(timezone.utc).isoformat()
    item = {
        "id":         str(uuid.uuid4()),
        # owner comes from the validated JWT, not the request body — prevents
        # a caller from creating notes attributed to another user
        "owner":      owner,
        "title":      title,
        "note":       note,
        "created_at": now,
        "updated_at": now,
    }

    get_container().create_item(body=item)
    return resp(201, {"id": item["id"], "title": item["title"], "note": item["note"]})


# ── GET /api/notes ─────────────────────────────────────────────────────────────

@app.route(route="notes", methods=["GET"])
def list_notes(req: func.HttpRequest) -> func.HttpResponse:
    owner = validate_token(req)
    if not owner:
        return resp(401, {"error": "Unauthorized"})

    # enable_cross_partition_query=False keeps the query within the owner's
    # partition — guards against a full-scan if the WHERE clause is ever lost
    items = list(get_container().query_items(
        query="SELECT c.id, c.title, c.note, c.created_at, c.updated_at FROM c WHERE c.owner = @owner",
        parameters=[{"name": "@owner", "value": owner}],
        enable_cross_partition_query=False,
    ))
    return resp(200, {"items": items})


# ── GET /api/notes/{id} ────────────────────────────────────────────────────────

@app.route(route="notes/{id}", methods=["GET"])
def get_note(req: func.HttpRequest) -> func.HttpResponse:
    owner = validate_token(req)
    if not owner:
        return resp(401, {"error": "Unauthorized"})

    note_id = req.route_params.get("id")
    try:
        # Point read with partition_key=owner is O(1) and implicitly rejects
        # items that belong to a different owner's partition
        item = get_container().read_item(item=note_id, partition_key=owner)
        return resp(200, {
            "id":         item["id"],
            "title":      item["title"],
            "note":       item["note"],
            "created_at": item["created_at"],
            "updated_at": item["updated_at"],
        })
    except exceptions.CosmosResourceNotFoundError:
        return resp(404, {"error": "Note not found"})


# ── PUT /api/notes/{id} ────────────────────────────────────────────────────────

@app.route(route="notes/{id}", methods=["PUT"])
def update_note(req: func.HttpRequest) -> func.HttpResponse:
    owner = validate_token(req)
    if not owner:
        return resp(401, {"error": "Unauthorized"})

    note_id = req.route_params.get("id")
    try:
        body = req.get_json()
    except ValueError:
        return resp(400, {"error": "Invalid JSON"})

    container = get_container()
    try:
        # Read before write — the Cosmos DB SQL API requires a full item
        # replacement; partial patch is not available on this API version
        item = container.read_item(item=note_id, partition_key=owner)
    except exceptions.CosmosResourceNotFoundError:
        return resp(404, {"error": "Note not found"})

    item["title"]      = body.get("title", item["title"]).strip()
    item["note"]       = body.get("note",  item["note"]).strip()
    item["updated_at"] = datetime.now(timezone.utc).isoformat()

    container.replace_item(item=note_id, body=item)
    return resp(200, {
        "id":         item["id"],
        "title":      item["title"],
        "note":       item["note"],
        "updated_at": item["updated_at"],
    })


# ── DELETE /api/notes/{id} ─────────────────────────────────────────────────────

@app.route(route="notes/{id}", methods=["DELETE"])
def delete_note(req: func.HttpRequest) -> func.HttpResponse:
    owner = validate_token(req)
    if not owner:
        return resp(401, {"error": "Unauthorized"})

    note_id = req.route_params.get("id")
    try:
        get_container().delete_item(item=note_id, partition_key=owner)
    except exceptions.CosmosResourceNotFoundError:
        pass  # idempotent — safe to delete a note that no longer exists
    return resp(200, {"message": "Note deleted"})
