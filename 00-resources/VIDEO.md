#Azure #Serverless #AzureFunctions #CosmosDB #Terraform #Python #CRUD

*Build a Serverless CRUD API on Azure (Functions + Cosmos DB)*

Deploy a fully serverless notes API on Azure using Terraform, Azure Functions, and Cosmos DB. The backend runs on a Flex Consumption (FC1) Function App with Python, backed by a Cosmos DB SQL API database, with a static web frontend served directly from Blob Storage.

In this project we build a clean REST API with full Create, Read, Update, and Delete support — wired to a real database, deployed with a single script, and tested through a browser-based UI with no server to manage.

WHAT YOU'LL LEARN
• Deploying Azure Functions on the Flex Consumption (FC1) plan with Terraform
• Packaging and zip-deploying Python function code with remote build
• Provisioning Cosmos DB (SQL API) and wiring credentials into the Function App
• Hosting a static web frontend on Azure Blob Storage ($web container)
• Injecting runtime config into HTML templates using envsubst

INFRASTRUCTURE DEPLOYED
• Azure Function App (Flex Consumption / FC1, Python 3.11)
• Storage account for function code zip deployment
• Cosmos DB account with SQL API database and container
• Storage account hosting a static web frontend ($web container)
• App settings passing Cosmos DB endpoint and key to the Function App

GitHub
https://github.com/mamonaco1973/azure-crud-example

README
https://github.com/mamonaco1973/azure-crud-example/blob/main/README.md

TIMESTAMPS
00:00 Introduction
00:22 Architecture
00:51 Build the Code
01:07 Build Results
01:39 Demo
