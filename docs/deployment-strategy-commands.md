# Deployment strategy commands

This runbook triggers and verifies the repository's three application-delivery
strategies. GitHub Actions performs the deployment; local commands only create
a protected release tag, observe the workflow, and inspect Azure resources.

| Tag pattern     | Strategy                           | Platform                 |
| --------------- | ---------------------------------- | ------------------------ |
| `rolling-v*`    | Kubernetes `RollingUpdate`         | Azure Kubernetes Service |
| `canary-v*`     | Weighted revision traffic          | Azure Container Apps     |
| `blue-green-v*` | Staging-slot verification and swap | Azure App Service        |

Every release builds and scans the image once in `dev`, publishes it to the
platform's private ACR, and promotes the same immutable digest through
`dev -> test -> preprod -> prod`.

## Common setup

Run from the repository root. Do not commit the subscription ID.

```bash
export REPO="Jayalakshmikumar08/github-actions-ci-cd-delivery-pipeline"
export AZURE_SUBSCRIPTION_ID="<subscription-id>"

gh auth status
az account set --subscription "$AZURE_SUBSCRIPTION_ID"
az account show --query '{name:name,id:id,tenantId:tenantId}' --output table

git switch main
git pull --ff-only origin main
export RELEASE_SHA="$(git rev-parse origin/main)"
git merge-base --is-ancestor "$RELEASE_SHA" origin/main
```

Set a new version for each release:

```bash
export VERSION="1.0.5"
```

After pushing a strategy tag, resolve and watch its workflow run:

```bash
export RUN_ID="$(
  gh run list \
    --repo "$REPO" \
    --workflow application-delivery.yml \
    --limit 20 \
    --json databaseId,headBranch \
    --jq ".[] | select(.headBranch == \"$TAG\") | .databaseId" |
    head -n 1
)"

test -n "$RUN_ID"
gh run watch "$RUN_ID" --repo "$REPO" --exit-status
```

Inspect or cancel a run:

```bash
gh run view "$RUN_ID" --repo "$REPO"
gh run cancel "$RUN_ID" --repo "$REPO"
```

Protected GitHub Environments can pause preprod or prod. Review the exact
pending environments before approving them:

```bash
export PENDING_DEPLOYMENTS="$(
  gh api "repos/$REPO/actions/runs/$RUN_ID/pending_deployments"
)"

jq '[.[] | {environment: .environment.name, id: .environment.id}]' \
  <<<"$PENDING_DEPLOYMENTS"

export ENVIRONMENT_IDS="$(
  jq -c '[.[].environment.id]' <<<"$PENDING_DEPLOYMENTS"
)"

jq -n \
  --argjson environment_ids "$ENVIRONMENT_IDS" \
  --arg comment "Approved after reviewing the preceding stage" \
  '{environment_ids: $environment_ids, state: "approved", comment: $comment}' |
  gh api \
    --method POST \
    "repos/$REPO/actions/runs/$RUN_ID/pending_deployments" \
    --input -
```

Do not approve an empty list, an unexpected environment, or a stage whose
preceding verification failed.

## Rolling deployment on AKS

Yes, the AKS strategy is a real Kubernetes rolling update. The Helm chart uses
`RollingUpdate`, `maxSurge: 1`, `maxUnavailable: 0`, health probes, and an
atomic Helm upgrade with automatic rollback on failure.

The developer profile normally has one application replica. During a rollout,
Kubernetes creates the new pod, waits until it is ready, and only then removes
the old pod. The production profile uses multiple replicas and replaces them
progressively.

### Trigger the rolling release

```bash
export TAG="rolling-v${VERSION}"
git tag --annotate "$TAG" "$RELEASE_SHA" \
  --message "AKS rolling release ${VERSION}"
git push origin "$TAG"
```

### Connect to AKS

```bash
export AKS_RESOURCE_GROUP="rg-cicd-aks-shared"
export AKS_NAME="$(
  az aks list \
    --resource-group "$AKS_RESOURCE_GROUP" \
    --query "[?tags.strategy=='rolling'] | [0].name" \
    --output tsv
)"

test -n "$AKS_NAME"
az aks get-credentials \
  --resource-group "$AKS_RESOURCE_GROUP" \
  --name "$AKS_NAME" \
  --overwrite-existing
kubelogin convert-kubeconfig --login azurecli
```

### Verify a stage

Choose `dev`, `test`, `preprod`, or `prod`:

```bash
export STAGE="dev"
export NAMESPACE="delivery-demo-${STAGE}"

kubectl get deployment,pods,service,hpa \
  --namespace "$NAMESPACE" \
  --output wide
kubectl rollout status deployment/delivery-demo \
  --namespace "$NAMESPACE" \
  --timeout=10m
kubectl rollout history deployment/delivery-demo \
  --namespace "$NAMESPACE"
kubectl get deployment delivery-demo \
  --namespace "$NAMESPACE" \
  --output jsonpath='{.spec.strategy}{"\n"}{.spec.template.spec.containers[0].image}{"\n"}'
```

Watch pod replacement while a new rolling release is running:

```bash
kubectl get pods \
  --namespace "$NAMESPACE" \
  --selector app.kubernetes.io/name=delivery-demo \
  --watch
```

Non-production services are private `ClusterIP` services. Test them through an
authenticated port-forward:

```bash
kubectl port-forward \
  --namespace "$NAMESPACE" \
  service/delivery-demo 18080:80
```

In a second terminal:

```bash
curl --fail --silent http://127.0.0.1:18080/health/live | jq
curl --fail --silent http://127.0.0.1:18080/health/ready | jq
curl --fail --silent http://127.0.0.1:18080/deployment | jq
```

The response must show `strategy: "rolling"`, the selected stage, and the first
12 characters of the release commit.

The prod service is a public `LoadBalancer`:

```bash
export AKS_PUBLIC_IP="$(
  kubectl get service delivery-demo \
    --namespace delivery-demo-prod \
    --output jsonpath='{.status.loadBalancer.ingress[0].ip}'
)"

test -n "$AKS_PUBLIC_IP"
curl --fail --silent "http://${AKS_PUBLIC_IP}/deployment" | jq
```

## Canary deployment on Container Apps

For each stage, the workflow creates a candidate revision and moves it through
5%, 25%, 50%, and 100% traffic. Each step generates a fresh request sample and
waits for the corresponding closed Azure Monitor one-minute bucket. The gate
fails closed if the required sample is absent or its 5xx percentage is too high;
the previous revision is then restored automatically.

### Trigger the canary release

```bash
export TAG="canary-v${VERSION}"
git tag --annotate "$TAG" "$RELEASE_SHA" \
  --message "Container Apps canary release ${VERSION}"
git push origin "$TAG"
```

### Observe revision traffic

Choose `dev`, `test`, `preprod`, or `prod` while the workflow is running:

```bash
export STAGE="dev"
export CONTAINER_APPS_RESOURCE_GROUP="rg-cicd-containerapps-shared"
export CONTAINER_APP_QUERY="[?tags.strategy=='canary'"
CONTAINER_APP_QUERY+=" && tags.environment=='${STAGE}'] | [0].name"
export CONTAINER_APP_NAME="$(
  az containerapp list \
    --resource-group "$CONTAINER_APPS_RESOURCE_GROUP" \
    --query "$CONTAINER_APP_QUERY" \
    --output tsv
)"

test -n "$CONTAINER_APP_NAME"
export ACTIVE_REVISION_QUERY="[?properties.active].{revision:name,weight:properties.trafficWeight,health:properties.healthState,state:properties.runningState}"
while true; do
  date -u
  az containerapp revision list \
    --resource-group "$CONTAINER_APPS_RESOURCE_GROUP" \
    --name "$CONTAINER_APP_NAME" \
    --query "$ACTIVE_REVISION_QUERY" \
    --output table
  sleep 10
done
```

Stop the observation loop with `Ctrl+C`.

### Test the public endpoint

```bash
export CONTAINER_APP_FQDN="$(
  az containerapp show \
    --resource-group "$CONTAINER_APPS_RESOURCE_GROUP" \
    --name "$CONTAINER_APP_NAME" \
    --query properties.configuration.ingress.fqdn \
    --output tsv
)"

curl --fail --silent "https://${CONTAINER_APP_FQDN}/health/live" | jq
curl --fail --silent "https://${CONTAINER_APP_FQDN}/health/ready" | jq

for request in {1..20}; do
  curl --fail --silent "https://${CONTAINER_APP_FQDN}/deployment" |
    jq -c '{releaseSha,strategy,stage,instanceId}'
done
```

During a weighted step, responses can show both stable and candidate revisions.
After promotion, exactly one healthy active revision should have 100% traffic:

```bash
export PROMOTED_REVISION_QUERY="[?properties.active].{revision:name,weight:properties.trafficWeight,health:properties.healthState}"
az containerapp revision list \
  --resource-group "$CONTAINER_APPS_RESOURCE_GROUP" \
  --name "$CONTAINER_APP_NAME" \
  --query "$PROMOTED_REVISION_QUERY" \
  --output table
```

## Blue/green deployment on App Service

The App Service infrastructure and worker quota must be ready first. Until the
quota request is approved, do not trigger a blue/green release.

For each stage, the workflow deploys to `staging`, verifies readiness, starts a
swap preview, verifies again, completes the swap, and verifies production. A
failed verification resets the preview or swaps the last known good release
back.

### Trigger the blue/green release

```bash
export TAG="blue-green-v${VERSION}"
git tag --annotate "$TAG" "$RELEASE_SHA" \
  --message "App Service blue-green release ${VERSION}"
git push origin "$TAG"
```

### Inspect and test both slots

```bash
export STAGE="dev"
export APP_SERVICE_RESOURCE_GROUP="rg-cicd-appservice-shared"
export APP_SERVICE_QUERY="[?tags.strategy=='blue-green'"
APP_SERVICE_QUERY+=" && tags.environment=='${STAGE}'] | [0].name"
export APP_SERVICE_NAME="$(
  az webapp list \
    --resource-group "$APP_SERVICE_RESOURCE_GROUP" \
    --query "$APP_SERVICE_QUERY" \
    --output tsv
)"

test -n "$APP_SERVICE_NAME"
export PRODUCTION_HOST="$(
  az webapp show \
    --resource-group "$APP_SERVICE_RESOURCE_GROUP" \
    --name "$APP_SERVICE_NAME" \
    --query defaultHostName \
    --output tsv
)"
export STAGING_HOST="$(
  az webapp show \
    --resource-group "$APP_SERVICE_RESOURCE_GROUP" \
    --name "$APP_SERVICE_NAME" \
    --slot staging \
    --query defaultHostName \
    --output tsv
)"

curl --fail --silent "https://${PRODUCTION_HOST}/health/ready" | jq
curl --fail --silent "https://${PRODUCTION_HOST}/deployment" | jq
curl --fail --silent "https://${STAGING_HOST}/health/ready" | jq
curl --fail --silent "https://${STAGING_HOST}/deployment" | jq
```

Before the swap, production should show the stable release and staging the
candidate. After the swap, production must show `strategy: "blue-green"`, the
selected stage, and the new release SHA.

Inspect the slots and configured container digest without changing them:

```bash
az webapp deployment slot list \
  --resource-group "$APP_SERVICE_RESOURCE_GROUP" \
  --name "$APP_SERVICE_NAME" \
  --output table
az webapp config container show \
  --resource-group "$APP_SERVICE_RESOURCE_GROUP" \
  --name "$APP_SERVICE_NAME" \
  --slot staging \
  --output json
```

## Verify build-once promotion

For a completed release, the workflow must show one successful build followed
by dev, test, preprod, and prod using the digest emitted by dev:

```bash
gh run view "$RUN_ID" \
  --repo "$REPO" \
  --json conclusion,headSha,jobs \
  --jq '{conclusion,headSha,jobs:[.jobs[] | {name,status,conclusion}]}'
```

Do not delete or stop Azure resources until interactive testing is complete and
a separate cleanup is explicitly approved.
