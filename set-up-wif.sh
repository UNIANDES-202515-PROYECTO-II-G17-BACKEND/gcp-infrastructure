#!/usr/bin/env bash
set -euo pipefail

# ======== CONFIGURA ESTAS VARIABLES ========
PROJECT_ID="misw4301-g26"
REGION="us-central1"
ORG="UNIANDES-202515-PROYECTO-II-G17-BACKEND"
SA_ID="gh-actions-sa"
POOL_ID="gh-pool"
PROVIDER_ID="gh-provider-ms"
# ===========================================

echo ">> Using PROJECT_ID=$PROJECT_ID, ORG=$ORG, REGION=$REGION"

gcloud config set project "$PROJECT_ID" >/dev/null

PROJECT_NUMBER="$(gcloud projects describe "$PROJECT_ID" --format="value(projectNumber)")"
SA_EMAIL="${SA_ID}@${PROJECT_ID}.iam.gserviceaccount.com"

# 1) Habilitar APIs necesarias
echo ">> Enabling required APIs..."
gcloud services enable \
  iamcredentials.googleapis.com \
  artifactregistry.googleapis.com \
  run.googleapis.com \
  cloudresourcemanager.googleapis.com \
  --project "$PROJECT_ID"

# 2) Crear Service Account (si no existe)
if ! gcloud iam service-accounts describe "$SA_EMAIL" --project "$PROJECT_ID" >/dev/null 2>&1; then
  echo ">> Creating Service Account: $SA_EMAIL"
  gcloud iam service-accounts create "$SA_ID" \
    --project "$PROJECT_ID" \
    --display-name "GitHub Actions SA"
else
  echo ">> Service Account already exists: $SA_EMAIL"
fi

# 3) Asignar roles mínimos a la SA (push a AR + deploy a Cloud Run opcional)
echo ">> Granting roles to SA..."
gcloud projects add-iam-policy-binding "$PROJECT_ID" \
  --member="serviceAccount:${SA_EMAIL}" \
  --role="roles/artifactregistry.writer" >/dev/null

gcloud projects add-iam-policy-binding "$PROJECT_ID" \
  --member="serviceAccount:${SA_EMAIL}" \
  --role="roles/run.admin" >/dev/null

gcloud projects add-iam-policy-binding "$PROJECT_ID" \
  --member="serviceAccount:${SA_EMAIL}" \
  --role="roles/iam.serviceAccountUser" >/dev/null

# 4) Crear Workload Identity Pool (si no existe)
if ! gcloud iam workload-identity-pools describe "$POOL_ID" --location=global --project="$PROJECT_ID" >/dev/null 2>&1; then
  echo ">> Creating Workload Identity Pool: $POOL_ID"
  gcloud iam workload-identity-pools create "$POOL_ID" \
    --project="$PROJECT_ID" \
    --location="global" \
    --display-name="GitHub Pool"
else
  echo ">> Workload Identity Pool already exists: $POOL_ID"
fi

# 5) Crear Workload Identity Provider (si no existe)
#    Condición: solo tokens cuyo assertion.repository comience con "ORG/ms-"
PROVIDER_FULL="projects/${PROJECT_NUMBER}/locations/global/workloadIdentityPools/${POOL_ID}/providers/${PROVIDER_ID}"

if ! gcloud iam workload-identity-pools providers describe "$PROVIDER_ID" \
      --project="$PROJECT_ID" --location="global" --workload-identity-pool="$POOL_ID" >/dev/null 2>&1; then
  echo ">> Creating Workload Identity Provider: $PROVIDER_ID"
  gcloud iam workload-identity-pools providers create-oidc gh-provider-ms \
    --project="$PROJECT_ID" \
    --location="global" \
    --workload-identity-pool="$POOL_ID" \
    --display-name="gh-ms" \
    --issuer-uri="https://token.actions.githubusercontent.com" \
    --attribute-mapping="google.subject=assertion.sub,attribute.repository=assertion.repository,attribute.actor=assertion.actor,attribute.ref=assertion.ref" \
    --attribute-condition="attribute.repository.startsWith(\"${ORG}/ms-\")"

else
  echo ">> Workload Identity Provider already exists: $PROVIDER_ID"
fi

# 6) Vincular la SA al pool (binding amplio; la condición del provider ya restringe)
echo ">> Binding SA to WIF pool (principalSet/*)..."
gcloud iam service-accounts add-iam-policy-binding "$SA_EMAIL" \
  --role="roles/iam.workloadIdentityUser" \
  --member="principalSet://iam.googleapis.com/projects/${PROJECT_NUMBER}/locations/global/workloadIdentityPools/${POOL_ID}/*" \
  --project="$PROJECT_ID" >/dev/null

# 7) Mostrar valores para GitHub Secrets
echo
echo "=========================="
echo "  ✅ Setup COMPLETADO"
echo "=========================="
echo "👉 Usa estos valores en tu repositorio(s) de GitHub:"
echo "   - Secret WIF_PROVIDER:"
echo "       ${PROVIDER_FULL}"
echo "   - Secret WIF_SERVICE_ACCOUNT:"
echo "       ${SA_EMAIL}"
echo
echo "💡 Recuerda agregar Variables en GitHub:"
echo "   - REGION=${REGION}"
echo "   - PROJECT_ID=${PROJECT_ID}"
echo
echo "📦 Para empujar imágenes a Artifact Registry, asegúrate de tener creado el repo:"
echo "   gcloud artifacts repositories describe project-images --location=${REGION} --project=${PROJECT_ID} || \\"
echo "   gcloud artifacts repositories create project-images --repository-format=docker --location=${REGION} --description='Repo MS' --project=${PROJECT_ID}"
echo
