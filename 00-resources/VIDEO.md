#Azure #Serverless #AzureFunctions #ServiceBus #CosmosDB #EntraID #Terraform #Python #OpenAI #GenerativeAI

*Build an AI Image Pipeline on Azure (Functions + Service Bus + OpenAI)*

Turn any photo into a cartoon using a fully serverless, event-driven pipeline on Azure — provisioned with Terraform and deployed with a single script. Users sign in with Entra External ID, upload a photo, pick a cartoon style, and a queue-driven worker calls the OpenAI API to generate a stylized result. Originals and cartoons are stored privately in Blob Storage and served through short-lived SAS URLs.

In this project we build an asynchronous AI image-processing pipeline from scratch — the browser uploads directly to Blob Storage, Service Bus decouples the slow OpenAI inference call from the API response, and an Azure Function running Pillow normalizes the photo before sending it to gpt-image-1. The whole thing runs without a single VM.

WHAT YOU'LL LEARN
• Calling OpenAI gpt-image-1 images.edit from an Azure Function using an API key
• Using Service Bus to decouple a slow AI inference call from a synchronous API response
• Validating Entra External ID JWTs in Python code against the CIAM JWKS endpoint
• Implementing PKCE OAuth2 Authorization Code flow with Entra External ID in a static SPA
• Generating Blob SAS tokens for direct browser PUT upload and time-limited download
• Enforcing per-user daily quotas with a Cosmos DB range query — no secondary index required
• Associating an Entra app registration with a sign-up/sign-in user flow via the Graph API
• Provisioning Azure Functions FC1 Flex Consumption and RBAC role assignments with Terraform

INFRASTRUCTURE DEPLOYED
• Microsoft Entra External ID app registration (SPA platform, PKCE, no client secret)
• Azure Functions FC1 Flex Consumption (Python 3.11, 2048 MB): upload-url, generate, result, history, delete + Service Bus worker trigger
• Service Bus Standard namespace + cartoonify-jobs queue (3 min lock duration, batch size 1)
• Cosmos DB SQL API account, database cartoonify, container jobs (PK=/owner, per-item 7-day TTL)
• Blob Storage media account (originals + cartoons containers, 7-day lifecycle policy)
• Blob Storage web account (static SPA: index.html, callback.html, config.json, favicon.ico)
• RBAC role assignments: Service Bus Sender + Receiver, custom Cosmos DB SQL role scoped to the Function App managed identity

GitHub
https://github.com/mamonaco1973/azure-cartoonify

README
https://github.com/mamonaco1973/azure-cartoonify/blob/main/README.md

TIMESTAMPS
00:00 Introduction
00:14 Architecture
00:55 Build the Code
02:54 Build Results
03:41 Demo
