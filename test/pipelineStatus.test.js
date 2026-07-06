import assert from "node:assert/strict";
import { test } from "node:test";

import {
  createBuildManifest,
  normalizeSha,
  resolveReleaseChannel,
} from "../src/pipelineStatus.js";

test("normalizes empty and long commit hashes", () => {
  assert.equal(normalizeSha(""), "local");
  assert.equal(normalizeSha(undefined), "local");
  assert.equal(normalizeSha("1234567890abcdef"), "1234567890ab");
});

test("resolves release channels from branch names", () => {
  assert.equal(resolveReleaseChannel("main"), "stable");
  assert.equal(resolveReleaseChannel("release/2026-07"), "release-candidate");
  assert.equal(resolveReleaseChannel("feature/pipeline"), "preview");
});

test("creates build manifest with expected metadata", () => {
  const manifest = createBuildManifest({
    sha: "abcdef1234567890",
    refName: "main",
    runId: "42",
    createdAt: "2026-07-06T00:00:00.000Z",
  });

  assert.deepEqual(manifest, {
    application: "github-actions-ci-cd-delivery-pipeline",
    version: "abcdef123456",
    sha: "abcdef123456",
    refName: "main",
    runId: "42",
    releaseChannel: "stable",
    createdAt: "2026-07-06T00:00:00.000Z",
  });
});
