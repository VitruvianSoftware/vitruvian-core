#!/bin/bash
# Copyright (c) 2026 VitruvianSoftware
#
# Permission is hereby granted, free of charge, to any person obtaining a copy
# of this software and associated documentation files (the "Software"), to deal
# in the Software without restriction, including without limitation the rights
# to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
# copies of the Software, and to permit persons to whom the Software is
# furnished to do so, subject to the following conditions:
#
# The above copyright notice and this permission notice shall be included in
# all copies or substantial portions of the Software.
#
# THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
# IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
# FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
# AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
# LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
# OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE
# SOFTWARE.

# Deployment script for Google Cloud Run
# Usage: ./deploy.sh [PROJECT_ID] [REGION]

set -e

PROJECT_ID=${1:-$(gcloud config get-value project)}
REGION=${2:-us-central1}
SERVICE_NAME="oauth-user-inspector"

echo "🚀 Deploying OAuth User Inspector to Google Cloud Run"
echo "Project: $PROJECT_ID"
echo "Region: $REGION"
echo "Service: $SERVICE_NAME"

# Enable required APIs
echo "📋 Enabling required Google Cloud APIs..."
gcloud services enable cloudbuild.googleapis.com
gcloud services enable run.googleapis.com
gcloud services enable containerregistry.googleapis.com
gcloud services enable secretmanager.googleapis.com

# Grant Secret Manager access to Cloud Run service account
echo "🔐 Setting up Secret Manager permissions..."
PROJECT_NUMBER=$(gcloud projects describe $PROJECT_ID --format="value(projectNumber)")
CLOUD_RUN_SA="$PROJECT_NUMBER-compute@developer.gserviceaccount.com"

# Grant Secret Manager Secret Accessor role to Cloud Run service account
gcloud projects add-iam-policy-binding $PROJECT_ID \
	--member="serviceAccount:$CLOUD_RUN_SA" \
	--role="roles/secretmanager.secretAccessor" || echo "⚠️  Permission may already exist"

# Build and deploy using Cloud Build
echo "🔨 Building and deploying with Cloud Build..."
gcloud builds submit --config cloudbuild.yaml

echo "✅ Deployment complete!"
echo "🌐 Your service will be available at:"
gcloud run services describe $SERVICE_NAME --region=$REGION --format="value(status.url)"
