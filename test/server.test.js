import assert from "node:assert/strict";
import { test } from "node:test";

import { createApplication } from "../src/server.js";

async function withServer(callback) {
  const application = createApplication({
    releaseSha: "abcdef1234567890",
    deploymentStrategy: "canary",
    deploymentStage: "preprod",
    instanceId: "revision-green",
    port: 0,
  });
  await new Promise((resolve) =>
    application.server.listen(0, "127.0.0.1", resolve),
  );
  const { port } = application.server.address();

  try {
    await callback(`http://127.0.0.1:${port}`);
  } finally {
    await new Promise((resolve) => application.server.close(resolve));
  }
}

test("reports liveness and release-aware readiness", async () => {
  await withServer(async (baseUrl) => {
    const live = await fetch(`${baseUrl}/health/live`);
    const ready = await fetch(`${baseUrl}/health/ready`);

    assert.equal(live.status, 200);
    assert.deepEqual(await live.json(), { status: "live" });
    assert.equal(ready.status, 200);
    assert.deepEqual(await ready.json(), {
      status: "ready",
      releaseSha: "abcdef123456",
    });
  });
});

test("returns version metadata and a 404 for unknown routes", async () => {
  await withServer(async (baseUrl) => {
    const version = await fetch(`${baseUrl}/version`);
    const missing = await fetch(`${baseUrl}/missing`);

    assert.equal(version.status, 200);
    const metadata = await version.json();
    assert.equal(metadata.releaseSha, "abcdef123456");
    assert.equal(metadata.strategy, "canary");
    assert.equal(metadata.stage, "preprod");
    assert.equal(metadata.instanceId, "revision-green");
    assert.equal(missing.status, 404);
  });
});

test("renders a strategy-specific dashboard and deployment API", async () => {
  await withServer(async (baseUrl) => {
    const page = await fetch(baseUrl);
    const deployment = await fetch(`${baseUrl}/deployment`);
    const html = await page.text();
    const metadata = await deployment.json();

    assert.equal(page.status, 200);
    assert.match(html, /Live Azure deployment strategy lab/);
    assert.match(html, /Canary/);
    assert.match(html, /5% → 25% → 50% → 100%/);
    assert.match(page.headers.get("content-security-policy"), /nonce-/);
    assert.equal(page.headers.get("x-content-type-options"), "nosniff");
    assert.equal(page.headers.get("x-frame-options"), "DENY");
    assert.equal(metadata.strategy, "canary");
    assert.equal(metadata.platform, "Azure Container Apps");
    assert.equal(deployment.headers.get("x-release-sha"), "abcdef123456");
  });
});
