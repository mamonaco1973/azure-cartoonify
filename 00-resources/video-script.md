# Video Script — Serverless CRUD API on Azure with Functions and Cosmos DB

---

## Introduction

[ Opening Sequence ]

"Do you need a secure authenticated serverless API on Azure?"

[ Architecture diagram — walk through it left to right: browser, storage account, Function App, Cosmos DB ]

"In this project we build a serverless notes API using an Azure Function App and Cosmos DB. The API is fully secured with an Entra ID Tenant.

[ Show Build Roll ]

"Follow along and in minutes you'll have a working authenticated API running in Azure."

---

## Architecture

[ Full diagram ]

"Let's walk through the architecture before we build."

[ Highlight browser and storage account ]

"The user opens a static web app from a storage account and signs in with Entra ID.

[ Entra ID then JWT ]

The Entra ID login returns a JWT and that token is sent with every API request.

[ Function App ]

"The function app itself validates the bearer token before the request is allowed."

[ Show CosmosDB ]

"The funcion app stores the notes in the Cosmos DB table."

[ Owner Field ]

The owner field is scoped to the authenticated user.

---

## Build the Code

[ Terminal — running ./apply.sh ]

"The whole deployment is one script — apply.sh. Three phases."

[ Terminal — Phase 1: Terraform apply ]

"Phase one: Terraform provisions the Function App and Cosmos DB — storage account for the code, the database, the app itself, all wired together."

[ Terminal — Phase 2: zip deploy ]

"Phase two: the Python code gets zipped and pushed to Azure with --build-remote. Dependencies install in the cloud — no local Python needed."

[ Terminal — Phase 3: webapp Terraform ]

"Phase three: envsubst injects the Function App URL into the HTML template. Terraform drops the file into storage account and the site is live."

[ Terminal — deployment complete, URLs printed ]

"API URL. Website URL. Done."

---

## Build Results

[ Azure Portal — Resource Groups ]

"Two resource groups — one for the Function App and Cosmos DB, one for the web frontend."

[ Azure Portal — Function App, Flex Consumption plan visible ]

"Function App on FC1. Python 3.11. Cosmos DB connection settings in app settings."

[ Azure Portal — Cosmos DB container ]

"Cosmos DB with a notes container. Partition key is owner."

[ Azure Portal — storage account, $web container ]

"Static website enabled. index.html in the $web container, ready to serve."

[ Browser — Notes Demo loads ]

"Open the URL. The app is live."

---

## Demo

Navigate to the URL to launch the notes application.

Sign in with an existing account or create a new one.

We're now authenticated into the app.

Open the browser debugger so we can watch the API calls.

Create a new note.

The post call is made with the JWT as a bearer token.

Now update the node.

A put call is made with the bearer token.

Delete the note.

A delete call is made with the bearer token.

In this demo we've exercised every API endpoint, all secured with JWT bearer tokens.

---
