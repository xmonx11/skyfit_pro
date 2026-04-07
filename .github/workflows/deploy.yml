name: Build and Deploy to Cloud Run

on:
  push:
    branches: [main]

jobs:
  deploy:
    runs-on: ubuntu-latest

    steps:
      - uses: actions/checkout@v4

      - name: Authenticate to GCP
        uses: google-github-actions/auth@v2
        with:
          credentials_json: ${{ secrets.GCP_SA_KEY }}

      - name: Get secrets from Secret Manager
        id: secrets
        uses: google-github-actions/get-secretmanager-secrets@v2
        with:
          secrets: |-
            FIREBASE_API_KEY:skyfitpro-b293c/FIREBASE_API_KEY
            FIREBASE_APP_ID:skyfitpro-b293c/FIREBASE_APP_ID
            FIREBASE_AUTH_DOMAIN:skyfitpro-b293c/FIREBASE_AUTH_DOMAIN
            FIREBASE_PROJECT_ID:skyfitpro-b293c/FIREBASE_PROJECT_ID
            FIREBASE_STORAGE_BUCKET:skyfitpro-b293c/FIREBASE_STORAGE_BUCKET
            FIREBASE_MESSAGING_SENDER_ID:skyfitpro-b293c/FIREBASE_MESSAGING_SENDER_ID
            OPENWEATHER_API_KEY:skyfitpro-b293c/OPENWEATHER_API_KEY

      - name: Set up Docker Buildx
        uses: docker/setup-buildx-action@v3

      - name: Configure Docker for Artifact Registry
        run: gcloud auth configure-docker asia-southeast1-docker.pkg.dev --quiet

      - name: Build and Push Docker Image
        run: |
          docker build \
            --build-arg FIREBASE_API_KEY=${{ steps.secrets.outputs.FIREBASE_API_KEY }} \
            --build-arg FIREBASE_AUTH_DOMAIN=${{ steps.secrets.outputs.FIREBASE_AUTH_DOMAIN }} \
            --build-arg FIREBASE_PROJECT_ID=${{ steps.secrets.outputs.FIREBASE_PROJECT_ID }} \
            --build-arg FIREBASE_STORAGE_BUCKET=${{ steps.secrets.outputs.FIREBASE_STORAGE_BUCKET }} \
            --build-arg FIREBASE_MESSAGING_SENDER_ID=${{ steps.secrets.outputs.FIREBASE_MESSAGING_SENDER_ID }} \
            --build-arg FIREBASE_APP_ID=${{ steps.secrets.outputs.FIREBASE_APP_ID }} \
            --build-arg OPENWEATHER_API_KEY=${{ steps.secrets.outputs.OPENWEATHER_API_KEY }} \
            -t asia-southeast1-docker.pkg.dev/skyfitpro-b293c/skyfit-pro/app:${{ github.sha }} \
            .
          docker push asia-southeast1-docker.pkg.dev/skyfitpro-b293c/skyfit-pro/app:${{ github.sha }}

      - name: Deploy to Cloud Run
        uses: google-github-actions/deploy-cloudrun@v2
        with:
          service: skyfit-pro
          region: asia-southeast1
          image: asia-southeast1-docker.pkg.dev/skyfitpro-b293c/skyfit-pro/app:${{ github.sha }}
          project_id: skyfitpro-b293c