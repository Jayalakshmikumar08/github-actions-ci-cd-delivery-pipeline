# Azure infrastructure

App Service, Container Apps and AKS are independent subscription-scope Bicep
deployments. There is deliberately no entry point that deploys all platforms.

| Entry point                          | Resource-group module             | Purpose                                                                                              |
| ------------------------------------ | --------------------------------- | ---------------------------------------------------------------------------------------------------- |
| `app-service/main.bicep`             | `app-service/foundation.bicep`    | Private ACR, Log Analytics, App Service plan and shared runtime pull identity                        |
| `app-service/workload-main.bicep`    | `app-service/workload.bicep`      | One stage app and staging slot using the immutable private-ACR digest                                |
| `container-apps/main.bicep`          | `container-apps/foundation.bicep` | Private ACR, Log Analytics, managed environment and shared runtime pull identity                     |
| `container-apps/workload-main.bicep` | `container-apps/workload.bicep`   | One stage multi-revision Container App using the immutable private-ACR digest                        |
| `aks/main.bicep`                     | `aks/platform.bicep`              | ACR, Log Analytics and Free-tier AKS cluster; one managed namespace per stage with scoped Azure RBAC |

Every platform entry point requires an allowed `stage` value: `dev`, `test`, `preprod`
or `prod`. Configure the same resource-group name in all four GitHub
infrastructure and application Environments for a platform. Repeated
deployments reconcile the same shared capacity and add or update only the
selected stage workload.

Every entry point also accepts `deploymentProfile`, allowed as `developer` or
`production` and defaulting to `developer`. Developer mode selects P0v4 App
Service, Basic ACR, Container Apps scale-to-zero, capped logging and one
`Standard_D2s_v4` AKS node. Production mode restores P0v3 zone redundancy,
Standard ACR, always-ready Container Apps, full diagnostics and a zonal
three-to-five-node `Standard_D4ds_v5` pool. The AKS application workflow passes
the same profile into Helm to select matching replica, HPA and PDB values.
Profiles are initial target configurations, not a promise that immutable AKS
node-pool or Container Apps environment properties can be changed in place.
Review `what-if` and plan a migration or recreation when promoting a target.

`modules/container-registry.bicep` and `modules/log-analytics.bicep` are shared
implementation modules. Each platform owns one module instance; no resource is
shared across App Service, Container Apps and AKS. The single Infrastructure
workflow selects and runs each platform through an independent stage chain.

`bootstrap/main.bicep` creates a GitHub OIDC user-assigned identity with one
exact federated credential per supplied Environment. The developer-subscription
profile invokes it six times: one plan identity, three platform infrastructure
identities and one application identity each for Container Apps and AKS. It is
a trust-root template for a central platform/IAM process; it does not deploy a
target platform. The workload pipeline cannot safely create the identity used
to authenticate itself.

The plan identity receives a custom read/validate/what-if role without resource
write access. Infrastructure identities receive subscription deployment roles
only when `grantInfrastructureDeploymentRoles` is explicitly enabled.

App Service and Container Apps use a private-ACR two-phase flow. Foundation
creates the registry and grants pull/publish access, CI pushes the scanned build,
and workload Bicep consumes the resulting immutable digest. No public bootstrap
image or registry credential is required. AKS already deploys its application
separately after the cluster and ACR exist.
The application Helm chart has no fallback image: CI must supply the real
Bicep-created ACR repository and promoted digest. It creates a public Load
Balancer so rolling behavior can be observed from a browser; the release
workflow verifies that endpoint.

The matching GitHub workflow is the only supported platform deployment path.
Pull requests compile, validate and run `what-if`; reviewed changes on `main`
create or update dev, test, preprod and prod. See
[`docs/azure-setup.md`](../docs/azure-setup.md) for identities, variables and
approval gates.
