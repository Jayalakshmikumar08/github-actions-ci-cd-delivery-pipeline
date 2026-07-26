import assert from "node:assert/strict";
import { test } from "node:test";

import { normalizeSha, resolveReleaseChannel } from "../src/pipelineStatus.js";

test("normalizes empty and long commit hashes", () => {
  assert.equal(normalizeSha(""), "local");
  assert.equal(normalizeSha("   "), "local");
  assert.equal(normalizeSha(undefined), "local");
  assert.equal(normalizeSha("1234567890abcdef"), "1234567890ab");
});

test("resolves release channels from branch names", () => {
  assert.equal(resolveReleaseChannel("main"), "stable");
  assert.equal(resolveReleaseChannel("release/2026-07"), "release-candidate");
  assert.equal(resolveReleaseChannel("feature/pipeline"), "preview");
});
