# Azure and GitHub prerequisite guide

This public guide contains no tenant, subscription, identity or quota-request
identifiers. Record real environment values only in the approved private
operations record and GitHub Environment configuration.

Infrastructure is deployed only by GitHub Actions and Bicep. Provider
registration, quota approval, identity trust and GitHub Environment configuration
are control-plane prerequisites, not manual application deployments.

## Subscription model

The repository supports either:

- one cost-controlled subscription shared by dev, test, preprod and prod; or
- separate governed subscriptions for stronger production isolation.

No subscription ID is hardcoded in a workflow, Bicep template, Helm chart or
application file. Every job reads `AZURE_SUBSCRIPTION_ID` from its protected
GitHub Environment. Switching subscriptions therefore requires configuration
and identity bootstrap changes, not source-code edits.

For a shared developer subscription, each platform reuses one resource group
and chargeable capacity while retaining four stage workloads. Set
`AZURE_DEPLOYMENT_PROFILE=developer` in every infrastructure Environment and
every AKS application Environment:

| Platform       | Developer shared capacity                                         | Stage isolation                                                |
| -------------- | ----------------------------------------------------------------- | -------------------------------------------------------------- |
| App Service    | Basic ACR, capped Log Analytics and one-worker P0v4 plan          | Four apps with independent staging slots                       |
| Container Apps | Basic ACR, capped Log Analytics and non-zonal managed environment | Four scale-to-zero apps with independent revisions and traffic |
| AKS            | Basic ACR, capped Log Analytics and one-node Free-tier cluster    | Four managed namespaces with scoped Azure RBAC                 |

The alternative `production` profile uses a two-worker zone-redundant P0v3
plan, Standard ACRs, always-ready zone-redundant Container Apps and a zonal
three-to-five-node AKS pool. That profile demonstrates resilience but is not a
cost-appropriate default for a developer subscription.

A production landing zone should use separate subscriptions or governed
resource groups and appropriately sized Standard-tier AKS capacity.

## Azure account worksheet

Record these values privately before configuration:

| Required decision        | Purpose                                                |
| ------------------------ | ------------------------------------------------------ |
| Entra tenant             | Contains the GitHub delivery identities                |
| Subscription per stage   | Target of each protected Environment                   |
| Region                   | Must support every selected SKU and availability zones |
| Resource prefix          | Lowercase alphanumeric, 3–12 characters                |
| Platform resource groups | One shared group per platform in the lab profile       |
| Identity resource group  | Holds GitHub OIDC managed identities                   |
| Private image repository | `delivery-demo` in each platform-owned ACR             |

Do not commit the completed worksheet.

## Required providers

Register and wait for `Registered` in every target subscription:

- `Microsoft.App`
- `Microsoft.Authorization`
- `Microsoft.Compute`
- `Microsoft.ContainerRegistry`
- `Microsoft.ContainerService`
- `Microsoft.Insights`
- `Microsoft.ManagedIdentity`
- `Microsoft.Network`
- `Microsoft.OperationalInsights`
- `Microsoft.Quota`
- `Microsoft.Resources`
- `Microsoft.Storage`
- `Microsoft.Web`

Provider registration creates no workload. Do not perform it from an
application deployment job.

## Region and quota preflight

For the default `developer` profile, verify the selected region and subscription
allow:

- Linux App Service P0v4 plus at least one Total Regional App Service VM;
- Container Apps managed environments;
- Basic ACR;
- AKS and `Standard_D2s_v4`;
- Log Analytics; and
- a Standard Load Balancer and public IPv4 address.

The developer AKS profile uses one two-vCPU node and permits one temporary surge
node. Approve at least:

- 4 total regional vCPUs;
- 4 DSv4-family vCPUs; and
- one Standard public IPv4 address.

Do not substitute a burstable B-series VM to reduce the node price: AKS does
not support B-series VMs in System node pools. `Standard_D2s_v4` is the selected
developer floor because it is a supported two-vCPU D-series SKU and uses the
subscription's DSv4-family quota. The single node is fixed at one; the second
node exists only temporarily when the AKS upgrade operation uses `maxSurge: 1`.

The `production` profile instead requires `Standard_D4ds_v5` in zones 1–3 plus
24 total regional and 24 DDSv5-family vCPUs. Do not run AKS infrastructure when
the selected SKU reports `NotAvailableForSubscription`, even if the numerical
quota appears sufficient.

The developer profile is deliberately non-HA. It uses one P0v4 App Service
worker, Container Apps scale-to-zero, a one-node AKS pool, Basic ACRs, a 1 GB/day
Log Analytics cap and no optional platform diagnostic streams. Stop AKS while
the demo is idle to avoid node compute charges. Use `production` only after a
cost and quota review.

Select a profile before the first deployment to a target. AKS node-pool VM
family and availability zones, and Container Apps environment zone redundancy,
are not general-purpose in-place resize switches. Treat a later developer-to-
production move as a reviewed migration or recreation after `what-if`, ideally
into a separate production landing zone.

## Private-ACR first deployment

App Service and Container Apps use a two-phase infrastructure deployment:

1. Foundation Bicep creates the private ACR, shared capacity, runtime pull
   identity and ACR role assignments.
2. The same infrastructure OIDC identity publishes the already scanned build
   artifact to `delivery-demo` in that ACR.
3. Workload Bicep creates the app using the immutable ACR digest.

The promoted image must:

- be Linux/amd64;
- listen on port `8080`;
- return HTTP 200 from `/health/live` and `/health/ready`;
- run as non-root;
- be scanned; and
- use an immutable digest reference.

The workflow passes the digest directly between the publish and workload steps;
there is no public GHCR package and no `AZURE_BOOTSTRAP_IMAGE` variable. AKS
already creates the cluster and ACR before its separate application workflow,
so it does not need this foundation/workload split.

## GitHub Environments

Create 27 Environments:

| Platform       | Plan                        | Infrastructure pattern                         | Application pattern                          |
| -------------- | --------------------------- | ---------------------------------------------- | -------------------------------------------- |
| App Service    | `infra-app-service-plan`    | `infra-app-service-{dev,test,preprod,prod}`    | `app-app-service-{dev,test,preprod,prod}`    |
| Container Apps | `infra-container-apps-plan` | `infra-container-apps-{dev,test,preprod,prod}` | `app-container-apps-{dev,test,preprod,prod}` |
| AKS            | `infra-aks-plan`            | `infra-aks-{dev,test,preprod,prod}`            | `app-aks-{dev,test,preprod,prod}`            |

The brace notation represents four separately created names.

Require reviewers for plan, preprod and production. Prevent self-review and
administrator bypass where supported. Restrict infrastructure apply jobs to
`main` and application jobs to their matching protected release tags.

## OIDC and client-secret identities

The shared-subscription lab profile uses six OIDC managed identities:

- one plan identity with three exact Environment credentials;
- one infrastructure identity per platform with four credentials each;
- one Container Apps delivery identity with four credentials; and
- one AKS delivery identity with four credentials.

This is six identities and 23 exact federated credentials. Exact credentials
remain necessary because Environment subjects do not use wildcards. Deploy
`infra/bootstrap/main.bicep` through the reviewed platform/IAM process with the
real GitHub owner, repository and `githubEnvironments` array.

Set `grantPlanRoles=true` only for the shared plan identity. Its custom role
permits subscription resource reads plus ARM validation and what-if, but omits
deployment and resource writes. Set `grantInfrastructureDeploymentRoles=true`
only for the three infrastructure identities. Both flags remain false for the
two OIDC application identities.

App Service uses one short-lived client-secret service principal in the lab
profile. Store its complete Azure credential JSON only as `AZURE_CREDENTIALS`
in each matching App Service Environment. Never commit or print it.

Production should use independently scoped and rotated identities per stage.

## Environment variables

Every infrastructure Environment requires:

- `AZURE_CLIENT_ID`
- `AZURE_TENANT_ID`
- `AZURE_SUBSCRIPTION_ID`
- `AZURE_LOCATION`
- `AZURE_RESOURCE_GROUP`
- `AZURE_RESOURCE_PREFIX`
- `AZURE_DEPLOYMENT_PROFILE` (`developer` or `production`)
- `DEPLOYMENT_PRINCIPAL_OBJECT_ID`

App Service and Container Apps infrastructure Environments additionally require
`PUBLISHER_PRINCIPAL_OBJECT_ID`, the object ID of that platform's infrastructure
OIDC identity. It receives repository-writer permission during foundation so it
can publish the first private image.

Every Container Apps and AKS application Environment requires:

- `AZURE_CLIENT_ID`
- `AZURE_TENANT_ID`
- `AZURE_SUBSCRIPTION_ID`
- `AZURE_RESOURCE_GROUP`

Every AKS application Environment additionally requires
`AZURE_DEPLOYMENT_PROFILE` with the same value as the AKS infrastructure
Environments. The other application workflows inherit their platform sizing
from Azure and do not consume the profile directly.

Every App Service application Environment requires:

- the `AZURE_CREDENTIALS` Environment secret; and
- `AZURE_RESOURCE_GROUP`.

For shared capacity, use the same resource-group value in all four
infrastructure and application Environments belonging to one platform.

## Switching to another subscription

Before changing any GitHub Environment:

1. Audit providers, region, policy, SKU restrictions and quota in the new
   subscription.
2. Deploy the OIDC bootstrap Bicep into the new subscription through the
   platform/IAM process.
3. Create or authorize the App Service service principal in the new
   subscription.
4. Record the new client IDs and principal object IDs.
5. Update `AZURE_SUBSCRIPTION_ID`, identity variables and credentials in the
   matching GitHub Environments.
6. Update region and resource-group variables if the target layout changed.
7. Run the three approved plan jobs and inspect every what-if result.
8. Apply infrastructure only after reviewers confirm the plans target the new
   subscription and contain no unexpected deletion.

Never reuse an old subscription's client ID or principal object ID without
creating and verifying its role assignments in the new subscription.

## Preflight checklist

- [ ] Tenant and target subscription per stage recorded privately.
- [ ] Providers registered.
- [ ] Region and required SKUs available.
- [ ] Compute and public-IP quotas sufficient.
- [ ] One deployment profile selected consistently for each platform.
- [ ] Private-ACR foundation/publish/workload flow reviewed.
- [ ] OIDC identities and exact Environment credentials deployed.
- [ ] App Service service principal and short-lived secret created.
- [ ] All GitHub Environments, variables, secrets and approvals configured.
- [ ] `main` and release tag patterns protected.
- [ ] Three production what-if plans reviewed.

Do not create a missing application resource from a workstation. Correct IaC,
identity, quota or Environment configuration and rerun the workflow.
