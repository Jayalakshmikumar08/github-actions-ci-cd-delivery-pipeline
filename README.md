# GitHub Actions CI/CD Delivery Pipeline

Portfolio project by Jayalakshmi Kumar.

## Scope

This repository demonstrates a production-style GitHub Actions CI/CD pattern for a small Node.js application.

The workflow covers the main delivery path:

1. Commit quality checks run on every pull request and push.
2. The application is built into a versioned artifact.
3. Automated tests validate the source logic.
4. Delivery runs only from `main`, downloads the build artifact and creates a release manifest for the target environment.

The project keeps delivery safe by writing a deployment manifest instead of pushing to real infrastructure. That makes the pipeline easy to review and run without cloud credentials.

## Pipeline Architecture

![GitHub Actions CI/CD pipeline](docs/pipeline.svg)

## Repository Structure

```text
.github/workflows/ci-cd.yml   Commit, build, test and delivery workflow
docs/pipeline.svg             Visual pipeline architecture
scripts/build.mjs             Produces the build artifact
scripts/deliver.mjs           Produces the delivery manifest
src/pipelineStatus.js         Build metadata helper functions
test/pipelineStatus.test.js   Unit tests using the Node.js test runner
.trunk/                       Static analysis and formatting configuration
```

## Pipeline Stages

- Commit quality: installs dependencies with `npm ci`, checks JavaScript syntax and runs Trunk static analysis.
- Build: creates a deterministic `dist/` artifact with build metadata.
- Test: validates the source logic with the built-in Node.js test runner.
- Delivery: runs after build and test pass, downloads the exact build artifact and creates a staging delivery manifest.

## Production Practices Demonstrated

- Pins GitHub Actions to immutable commit SHAs.
- Uses least-privilege workflow permissions.
- Separates build, test and delivery jobs with explicit `needs` dependencies.
- Publishes and reuses artifacts rather than rebuilding during delivery.
- Adds timeouts and concurrency control.
- Uses a GitHub Environment for the delivery job.
- Keeps secrets out of source control.
- Runs Trunk checks for YAML, Markdown, workflow and security scanning.

## Local Verification

```bash
npm ci
npm run lint
npm test
npm run build
npm run deliver
trunk check --all --no-fix --print-failures
```

Generated `dist/` and `release/` outputs are ignored by Git so the repository stays focused on source and pipeline code.

## Official References

- [GitHub Actions workflow syntax](https://docs.github.com/actions/using-workflows/workflow-syntax-for-github-actions)
- [Building and testing Node.js with GitHub Actions](https://docs.github.com/actions/guides/building-and-testing-nodejs)
- [Storing and sharing data with workflow artifacts](https://docs.github.com/en/actions/tutorials/store-and-share-data)
- [Using environments for deployment](https://docs.github.com/actions/deployment/targeting-different-environments/using-environments-for-deployment)
