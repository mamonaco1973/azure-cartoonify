# ================================================================================
# function_app.py — cartoonify Azure Functions
#
# HTTP endpoints (all JWT-authenticated via Entra External ID):
#   POST /api/upload-url       → Blob SAS upload token
#   POST /api/generate         → validate, quota check, enqueue SB, 202
#   GET  /api/result/{job_id}  → job status + SAS download URLs
#   GET  /api/history          → newest 50 jobs for owner
#   DELETE /api/history/{job_id} → delete job + blobs
#
# Worker (Service Bus queue trigger):
#   cartoonify_worker          → download original, gpt-image-1, upload cartoon
#
# Auth: JWT validated in code against Entra External ID JWKS. The sub claim
# becomes the Cosmos DB partition key (/owner), enforcing per-user isolation.
# ================================================================================

import base64
import io
import json
import logging
import os
import time
import uuid
from datetime import datetime, timedelta, timezone

import azure.functions as func
import requests
from azure.cosmos import CosmosClient
from azure.identity import DefaultAzureCredential
from azure.storage.blob import (
    BlobSasPermissions,
    BlobServiceClient,
    generate_blob_sas,
)
from openai import OpenAI
from PIL import Image, ImageOps
import jwt
from jwt.algorithms import RSAAlgorithm

app = func.FunctionApp(http_auth_level=func.AuthLevel.ANONYMOUS)

# ================================================================================
# Configuration (injected by Terraform via Function App settings)
# ================================================================================

COSMOS_ENDPOINT    = os.environ["COSMOS_ENDPOINT"]
COSMOS_DATABASE    = os.environ["COSMOS_DATABASE_NAME"]
COSMOS_CONTAINER   = os.environ["COSMOS_CONTAINER_NAME"]

MEDIA_ACCOUNT_NAME  = os.environ["MEDIA_ACCOUNT_NAME"]
MEDIA_ACCOUNT_KEY   = os.environ["MEDIA_ACCOUNT_KEY"]
MEDIA_BLOB_ENDPOINT = os.environ["MEDIA_BLOB_ENDPOINT"]

OPENAI_API_KEY = os.environ.get("OPENAI_API_KEY", "")

ENTRA_TENANT      = os.environ["ENTRA_TENANT_NAME"]
ENTRA_TENANT_ID   = os.environ["ENTRA_TENANT_ID"]
CLIENT_ID         = os.environ["ENTRA_CLIENT_ID"]

SB_NAMESPACE_FQDN = os.environ["SERVICEBUS_NAMESPACE_FQDN"]
SB_QUEUE_NAME     = os.environ["SERVICEBUS_QUEUE_NAME"]

# ================================================================================
# Constants
# ================================================================================

ALLOWED_STYLES = {
    "pixar_3d", "simpsons", "anime",
    "comic_book", "watercolor", "pencil_sketch",
}
ALLOWED_CONTENT_TYPES = {
    "image/jpeg": "jpg",
    "image/png":  "png",
    "image/webp": "webp",
}
MAX_UPLOAD_BYTES  = 5 * 1024 * 1024
DAILY_QUOTA       = 10
JOB_TTL_SECONDS   = 7 * 24 * 3600
SAS_UPLOAD_TTL    = 300
SAS_DOWNLOAD_TTL  = 4 * 3600
MAX_PROMPT_EXTRA  = 500
TARGET_SIZE       = 1024

# Style prompts — keys match ALLOWED_STYLES; full text stays server-side
STYLE_PROMPTS = {
    "pixar_3d": (
        "Pixar 3D animated portrait, subsurface skin shading, warm rim lighting, "
        "large expressive eyes, smooth stylized features, vibrant color grading, "
        "cinematic depth of field, high-quality render"
    ),
    "simpsons": (
        "The Simpsons animated style, bright yellow skin, bold black outlines, "
        "flat cel-shaded colors, D-shaped ears, overbite, Springfield cartoon aesthetic"
    ),
    "comic_book": (
        "Marvel comic book illustration, Ben-Day dot shading, bold ink outlines, "
        "dramatic shadows, saturated primary colors, dynamic superhero rendering"
    ),
    "anime": (
        "Japanese anime portrait, detailed cel-shading, vibrant hair, large luminous eyes, "
        "clean sharp lineart, soft highlight gloss, manga-style rendering"
    ),
    "watercolor": (
        "fine art watercolor portrait, loose wet-on-wet washes, soft color blooms, "
        "visible paper texture, delicate brushwork, impressionist light"
    ),
    "pencil_sketch": (
        "detailed graphite portrait sketch, cross-hatching, tonal shading, "
        "textured paper grain, charcoal smudge, monochrome rendering, artist sketchbook"
    ),
}

# ================================================================================
# Auth — Entra External ID JWT validation
# JWKS is cached per warm instance to avoid repeated network calls.
# ================================================================================

_jwks_cache = None


def _get_jwks():
    """Fetch the Entra External ID public key set, cached per instance.

    Uses ciamlogin.com (not login.microsoftonline.com) — no policy name
    suffix is needed in the discovery URL.

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
    or oid as the owner — this becomes the Cosmos DB partition key.

    Args:
        req: The incoming Azure Functions HTTP request.

    Returns:
        A string owner ID if valid, or None if missing or invalid.
    """
    auth = req.headers.get("Authorization", "")
    if not auth.startswith("Bearer "):
        return None
    token = auth[7:]
    try:
        jwks = _get_jwks()
        header = jwt.get_unverified_header(token)
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
        return claims.get("sub") or claims.get("oid")
    except Exception:
        return None


# ================================================================================
# Cosmos DB helpers
# ================================================================================

def get_container():
    """Return a Cosmos DB container client authenticated via managed identity.

    Creates a new CosmosClient on each call — the SDK manages HTTP connection
    pooling internally.

    Returns:
        A ContainerProxy for the cartoonify jobs container.
    """
    credential = DefaultAzureCredential()
    client = CosmosClient(COSMOS_ENDPOINT, credential=credential)
    return client.get_database_client(COSMOS_DATABASE).get_container_client(
        COSMOS_CONTAINER
    )


def resp(status: int, body) -> func.HttpResponse:
    """Serialize body as JSON and return an HttpResponse."""
    return func.HttpResponse(
        json.dumps(body),
        status_code=status,
        mimetype="application/json",
        headers={"Content-Type": "application/json"},
    )


# ================================================================================
# Blob Storage helpers — SAS token generation
# Account key is used for SAS signing (stored as a Function App setting).
# ================================================================================

def _make_upload_sas(container: str, blob_name: str) -> str:
    """Generate a write-only SAS URL for a single blob upload.

    Args:
        container: Blob container name (e.g. 'originals').
        blob_name: Blob path within the container.

    Returns:
        A full SAS URL the browser can PUT to directly.
    """
    expiry = datetime.now(timezone.utc) + timedelta(seconds=SAS_UPLOAD_TTL)
    token = generate_blob_sas(
        account_name=MEDIA_ACCOUNT_NAME,
        container_name=container,
        blob_name=blob_name,
        account_key=MEDIA_ACCOUNT_KEY,
        permission=BlobSasPermissions(create=True, write=True),
        expiry=expiry,
    )
    return f"{MEDIA_BLOB_ENDPOINT}{container}/{blob_name}?{token}"


def _make_download_sas(container: str, blob_name: str) -> str:
    """Generate a read-only SAS URL valid for SAS_DOWNLOAD_TTL seconds.

    Args:
        container: Blob container name.
        blob_name: Blob path within the container.

    Returns:
        A full SAS URL for reading the blob.
    """
    expiry = datetime.now(timezone.utc) + timedelta(seconds=SAS_DOWNLOAD_TTL)
    token = generate_blob_sas(
        account_name=MEDIA_ACCOUNT_NAME,
        container_name=container,
        blob_name=blob_name,
        account_key=MEDIA_ACCOUNT_KEY,
        permission=BlobSasPermissions(read=True),
        expiry=expiry,
    )
    return f"{MEDIA_BLOB_ENDPOINT}{container}/{blob_name}?{token}"


def _parse_blob_key(key: str):
    """Split a full blob key 'container/path/name' into (container, blob_name).

    Args:
        key: Full blob key string (e.g. 'originals/owner/job_id.jpg').

    Returns:
        Tuple of (container, blob_name).
    """
    parts = key.split("/", 1)
    return parts[0], parts[1]


# ================================================================================
# Job ID helpers
# ================================================================================

def make_job_id() -> str:
    """Return a lexicographically time-sortable job id: <ms:013d>-<hex8>."""
    ms = int(time.time() * 1000)
    return f"{ms:013d}-{uuid.uuid4().hex[:8]}"


def job_id_ms(job_id: str) -> int:
    """Extract the millisecond timestamp prefix from a job_id."""
    return int(job_id.split("-", 1)[0])


def start_of_utc_day_ms() -> int:
    """Return epoch ms of 00:00 UTC today — used for daily quota queries."""
    now_ms = int(time.time() * 1000)
    return (now_ms // 1000 // 86400) * 86400 * 1000


# ================================================================================
# POST /api/upload-url
# Returns a Blob SAS URL so the browser can PUT the image directly to storage.
# Replaces the S3 presigned POST in aws-cartoonify.
# ================================================================================

@app.route(route="upload-url", methods=["POST"])
def upload_url(req: func.HttpRequest) -> func.HttpResponse:
    owner = validate_token(req)
    if not owner:
        return resp(401, {"error": "Unauthorized"})

    try:
        body = req.get_json()
    except ValueError:
        return resp(400, {"error": "Invalid JSON"})

    content_type = body.get("content_type")
    if content_type not in ALLOWED_CONTENT_TYPES:
        return resp(400, {
            "error":   "Unsupported content_type",
            "allowed": sorted(ALLOWED_CONTENT_TYPES.keys()),
        })

    ext    = ALLOWED_CONTENT_TYPES[content_type]
    job_id = make_job_id()
    # key includes the container prefix so the browser and worker agree on paths
    blob_name = f"{owner}/{job_id}.{ext}"
    key       = f"originals/{blob_name}"

    sas_url = _make_upload_sas("originals", blob_name)

    logging.info("Issued upload SAS owner=%s job_id=%s key=%s", owner, job_id, key)

    return resp(200, {
        "job_id":  job_id,
        "key":     key,
        "url":     sas_url,
        "method":  "PUT",
        "headers": {"x-ms-blob-type": "BlockBlob", "Content-Type": content_type},
    })


# ================================================================================
# POST /api/generate
# Validates the request, enforces daily quota, writes job row, enqueues SB msg.
# ================================================================================

@app.route(route="generate", methods=["POST"])
def generate(req: func.HttpRequest) -> func.HttpResponse:
    owner = validate_token(req)
    if not owner:
        return resp(401, {"error": "Unauthorized"})

    try:
        body = req.get_json()
    except ValueError:
        return resp(400, {"error": "Invalid JSON"})

    job_id       = body.get("job_id")
    style        = body.get("style")
    key          = body.get("key")
    prompt_extra = (body.get("prompt_extra") or "").strip()

    if not job_id or not key:
        return resp(400, {"error": "Missing job_id or key"})

    if style not in ALLOWED_STYLES:
        return resp(400, {"error": "Unsupported style", "allowed": sorted(ALLOWED_STYLES)})

    if len(prompt_extra) > MAX_PROMPT_EXTRA:
        return resp(400, {"error": f"prompt_extra exceeds {MAX_PROMPT_EXTRA} chars"})

    # Defend against key path injection from another user
    expected_prefix = f"originals/{owner}/{job_id}."
    if not key.startswith(expected_prefix):
        return resp(400, {"error": "Key does not match owner/job_id"})

    # Confirm the upload landed before queuing the job
    blob_name = key[len("originals/"):]
    try:
        blob_client = BlobServiceClient(
            account_url=MEDIA_BLOB_ENDPOINT,
            credential=MEDIA_ACCOUNT_KEY,
        ).get_blob_client("originals", blob_name)
        blob_client.get_blob_properties()
    except Exception:
        return resp(400, {"error": "Original not uploaded yet"})

    # Daily quota — count today's jobs for this owner via Cosmos query
    container = get_container()
    start_prefix = f"{start_of_utc_day_ms():013d}-"
    query = (
        "SELECT VALUE COUNT(1) FROM c "
        "WHERE c.owner = @owner AND c.job_id >= @start"
    )
    params = [
        {"name": "@owner", "value": owner},
        {"name": "@start", "value": start_prefix},
    ]
    count_result = list(container.query_items(
        query=query,
        parameters=params,
        enable_cross_partition_query=False,
    ))
    count = count_result[0] if count_result else 0

    if count >= DAILY_QUOTA:
        return resp(429, {
            "error":  f"Daily limit of {DAILY_QUOTA} reached",
            "used":   count,
            "resets": "at 00:00 UTC",
        })

    # Write job row
    now = int(time.time())
    item = {
        "id":            job_id,
        "owner":         owner,
        "job_id":        job_id,
        "status":        "submitted",
        "style":         style,
        "original_key":  key,
        "created_at":    now,
        "created_at_ms": job_id_ms(job_id),
        "ttl":           now + JOB_TTL_SECONDS,
    }
    if prompt_extra:
        item["prompt_extra"] = prompt_extra
    container.create_item(body=item)

    # Enqueue Service Bus message
    from azure.servicebus import ServiceBusClient, ServiceBusMessage
    credential = DefaultAzureCredential()
    with ServiceBusClient(
        fully_qualified_namespace=SB_NAMESPACE_FQDN,
        credential=credential,
    ) as sb_client:
        with sb_client.get_queue_sender(queue_name=SB_QUEUE_NAME) as sender:
            sender.send_messages(ServiceBusMessage(json.dumps({
                "job_id":       job_id,
                "owner":        owner,
                "style":        style,
                "original_key": key,
                "prompt_extra": prompt_extra,
            })))

    logging.info("Submitted job_id=%s owner=%s style=%s", job_id, owner, style)
    return resp(202, {"job_id": job_id, "status": "submitted"})


# ================================================================================
# GET /api/result/{job_id}
# Returns current job status and SAS download URLs for original + cartoon.
# ================================================================================

@app.route(route="result/{job_id}", methods=["GET"])
def result(req: func.HttpRequest) -> func.HttpResponse:
    owner = validate_token(req)
    if not owner:
        return resp(401, {"error": "Unauthorized"})

    job_id = req.route_params.get("job_id")
    if not job_id:
        return resp(400, {"error": "Missing job_id"})

    try:
        item = get_container().read_item(item=job_id, partition_key=owner)
    except Exception:
        return resp(404, {"error": "Not found"})

    out = {
        "job_id":     item["job_id"],
        "status":     item.get("status"),
        "style":      item.get("style"),
        "created_at": item.get("created_at"),
    }

    original_key = item.get("original_key")
    if original_key:
        container_name, blob_name = _parse_blob_key(original_key)
        out["original_url"] = _make_download_sas(container_name, blob_name)

    cartoon_key = item.get("cartoon_key")
    if cartoon_key:
        container_name, blob_name = _parse_blob_key(cartoon_key)
        out["cartoon_url"] = _make_download_sas(container_name, blob_name)

    if item.get("error_message"):
        out["error_message"] = item["error_message"]

    return resp(200, out)


# ================================================================================
# GET /api/history
# Returns the newest 50 jobs for the authenticated user.
# ================================================================================

@app.route(route="history", methods=["GET"])
def history(req: func.HttpRequest) -> func.HttpResponse:
    owner = validate_token(req)
    if not owner:
        return resp(401, {"error": "Unauthorized"})

    # ORDER BY job_id DESC gives newest-first because job_id is time-sortable
    query = (
        "SELECT TOP 50 * FROM c "
        "WHERE c.owner = @owner "
        "ORDER BY c.job_id DESC"
    )
    items = list(get_container().query_items(
        query=query,
        parameters=[{"name": "@owner", "value": owner}],
        enable_cross_partition_query=False,
    ))

    result_items = []
    for item in items:
        entry = {
            "job_id":     item["job_id"],
            "status":     item.get("status"),
            "style":      item.get("style"),
            "created_at": item.get("created_at"),
        }
        original_key = item.get("original_key")
        if original_key:
            c, b = _parse_blob_key(original_key)
            entry["original_url"] = _make_download_sas(c, b)
        cartoon_key = item.get("cartoon_key")
        if cartoon_key:
            c, b = _parse_blob_key(cartoon_key)
            entry["cartoon_url"] = _make_download_sas(c, b)
        if item.get("error_message"):
            entry["error_message"] = item["error_message"]
        result_items.append(entry)

    return resp(200, {"items": result_items, "count": len(result_items)})


# ================================================================================
# DELETE /api/history/{job_id}
# Removes a job row and its blobs. Owner enforcement via partition key read.
# ================================================================================

@app.route(route="history/{job_id}", methods=["DELETE"])
def delete_history(req: func.HttpRequest) -> func.HttpResponse:
    owner = validate_token(req)
    if not owner:
        return resp(401, {"error": "Unauthorized"})

    job_id = req.route_params.get("job_id")
    if not job_id:
        return resp(400, {"error": "Missing job_id"})

    container = get_container()
    try:
        item = container.read_item(item=job_id, partition_key=owner)
    except Exception:
        return resp(404, {"error": "Not found"})

    # Delete blobs before removing the row so there is no orphan state
    blob_service = BlobServiceClient(
        account_url=MEDIA_BLOB_ENDPOINT,
        credential=MEDIA_ACCOUNT_KEY,
    )
    for key in (item.get("original_key"), item.get("cartoon_key")):
        if key:
            c, b = _parse_blob_key(key)
            try:
                blob_service.get_blob_client(c, b).delete_blob()
            except Exception:
                pass  # blob may already be gone; non-fatal

    container.delete_item(item=job_id, partition_key=owner)

    logging.info("Deleted job_id=%s owner=%s", job_id, owner)
    return resp(200, {"job_id": job_id, "deleted": True})


# ================================================================================
# Service Bus queue trigger — cartoonify worker
# Replaces the SQS-triggered Lambda container in aws-cartoonify.
# ================================================================================

@app.function_name(name="cartoonify_worker")
@app.service_bus_queue_trigger(
    arg_name="msg",
    queue_name="%SERVICEBUS_QUEUE_NAME%",
    connection="ServiceBusConnection",
)
def cartoonify_worker(msg: func.ServiceBusMessage) -> None:
    """Process a cartoonify job from the Service Bus queue.

    Reads the job message, downloads the original image, normalizes it,
    calls gpt-image-1 images.edit with the style prompt, uploads the
    cartoon to blob storage, and updates the Cosmos DB job status.

    Raises on hard failure so the Service Bus SDK can retry / dead-letter.
    Soft failures (quota exceeded, content filtered) update status=error
    without re-raising so the message is not redelivered.
    """
    raw  = msg.get_body().decode("utf-8")
    body = json.loads(raw)

    job_id       = body["job_id"]
    owner        = body["owner"]
    style        = body["style"]
    original_key = body["original_key"]
    prompt_extra = body.get("prompt_extra") or ""

    logging.info("Worker: job=%s owner=%s style=%s", job_id, owner, style)

    cosmos = get_container()

    def _mark(status: str, **extra):
        patch = {"status": status, **extra}
        if status in ("complete", "error"):
            patch["completed_at"] = int(time.time())
        cosmos.patch_item(
            item=job_id,
            partition_key=owner,
            patch_operations=[
                {"op": "replace", "path": f"/{k}", "value": v}
                for k, v in patch.items()
            ],
        )

    try:
        _mark("processing")

        # 1. Download original from blob storage
        blob_service = BlobServiceClient(
            account_url=MEDIA_BLOB_ENDPOINT,
            credential=MEDIA_ACCOUNT_KEY,
        )
        container_name, blob_name = _parse_blob_key(original_key)
        src_bytes = blob_service.get_blob_client(
            container_name, blob_name
        ).download_blob().readall()

        # 2. Normalize: EXIF-transpose, RGB, center-square-crop, 1024×1024 PNG
        img = Image.open(io.BytesIO(src_bytes))
        img = ImageOps.exif_transpose(img)
        img = img.convert("RGB")
        w, h   = img.size
        side   = min(w, h)
        left   = (w - side) // 2
        top    = (h - side) // 2
        img    = img.crop((left, top, left + side, top + side))
        img    = img.resize((TARGET_SIZE, TARGET_SIZE), Image.LANCZOS)
        buf    = io.BytesIO()
        img.save(buf, format="PNG", optimize=True)
        png_bytes = buf.getvalue()

        # 3. Call gpt-image-1 images.edit via api.openai.com
        if not OPENAI_API_KEY:
            raise RuntimeError(
                "An OpenAI API key is required to generate cartoons. "
                "Set OPENAI_API_KEY and re-run apply.sh."
            )

        prompt = STYLE_PROMPTS.get(style, "")
        if prompt_extra:
            prompt = f"{prompt}, {prompt_extra}"

        openai_client = OpenAI(api_key=OPENAI_API_KEY)

        logging.info("Calling gpt-image-1 style=%s job=%s", style, job_id)
        image_response = openai_client.images.edit(
            model="gpt-image-1",
            image=("image.png", png_bytes, "image/png"),
            prompt=prompt,
            size="1024x1024",
            n=1,
        )
        cartoon_bytes = base64.b64decode(image_response.data[0].b64_json)

        # 4. Upload cartoon to blob storage
        cartoon_blob = f"{owner}/{job_id}.png"
        cartoon_key  = f"cartoons/{cartoon_blob}"
        blob_service.get_blob_client("cartoons", cartoon_blob).upload_blob(
            cartoon_bytes,
            overwrite=True,
            content_settings={"content_type": "image/png"},
        )

        # 5. Mark complete
        _mark("complete", cartoon_key=cartoon_key)
        logging.info("Worker: completed job=%s → %s", job_id, cartoon_key)

    except Exception as e:
        logging.exception("Worker: failed job=%s: %s", job_id, e)
        try:
            _mark("error", error_message=str(e)[:500])
        except Exception:
            logging.exception("Worker: failed to mark error for job=%s", job_id)
        # Re-raise so Service Bus can retry / dead-letter on hard failures
        raise
