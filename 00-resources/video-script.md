# Video Script — Serverless CRUD API on Azure with Functions and Cosmos DB

---

## Introduction
 
[ Opening Sequence ]

“Do you want to build an AI-powered image pipeline on Azure?”

[ Show Diagram ]

"In this project, we build a fully serverless pipeline that turns photos into cartoons using Azure and Open AI."

[ Build B Roll ]

Follow along and in minutes you’ll have a fully working AI pipeline running on Azure.

---

## Architecture

[ Full diagram ]

"Let's walk through the architecture before we build."

[ Diagram then Congito ]

"First, the user signs into the web application using an Entra ID external tenant.

[ Choose File then Diagam ]

"When the user selects “Choose File”, the image is uploaded to a storage account."

[  Cartoonify ]

When the user selects “Cartoonify”, the API does two things:

[ Highlight Cosmos DB]

It creates a job record in Cosmos DB

[ Highlight SQS queue ]

Then it sends a message to the image processing service bus.

[ Highlight Lambda ]

"The service bus triggers the worker function."

[ Show bedrock ]

"The worker function calls Open AI to generate the cartoon."

[ Show Open AI page]

"You'll need to provide an Open AI API key for the image generation processing".

[ Show S3 Media Bucket]

"The generated image is written back to the storage account."

[ Final Dynamo DB State]

When processing completes, the job status is updated in Cosmos DB.

[ Show final result ]

The web application refreshes and displays the generated image.

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

Now re-run the check env script after setting the environment variables.

Note the warning about the Open AI API key - This is necessary for the image generation and can be added later.

If you need help setting up Azure and terraform check out our Azure Setup video.

Once that's done run the apply script to start the build.

---

## Build Results

Three storage accounts are created for this project.

The first account hosts the public web application.

The second account stores the uploaded source images and generated cartoons.

The third account stores the azure functions.

Identity and access is handled by an Entra ID External tenant.

The serverless API is implemented with an Azure Function App.

The image generation pipeline is drived by an azure service bus queue.

Cosmos DB stores the status of each image generation job.

When a message is processed, the worker function calls Open AI to generate the cartoon image.

An API key must be specified to generate images.

The generated image is written back to the media storage account.

The Cosmos DB job record is updated to complete.

When the application refreshes, the generated results are displayed.


---

## Demo

Navigate to the web application URL.

Sign in using the external Entra ID tenant.

Select choose file and upload a test image.

Select the Pixar 3D style, then click Cartoonify to start the image generation pipeline.

The application displays the image generation life cycle in the left panel.

Now try some different styles.

The application displays a gallery of your previous results.

---
