export function normalizeSha(sha) {
  if (!sha || typeof sha !== "string") {
    return "local";
  }

  return sha.trim().slice(0, 12) || "local";
}

export function resolveReleaseChannel(refName) {
  if (refName === "main") {
    return "stable";
  }

  if (refName?.startsWith("release/")) {
    return "release-candidate";
  }

  return "preview";
}

export function createBuildManifest({
  sha = process.env.GITHUB_SHA,
  refName = process.env.GITHUB_REF_NAME,
  runId = process.env.GITHUB_RUN_ID,
  createdAt = new Date().toISOString(),
} = {}) {
  const sourceRef = refName || "local";

  return {
    application: "github-actions-ci-cd-delivery-pipeline",
    version: normalizeSha(sha),
    sha: normalizeSha(sha),
    refName: sourceRef,
    runId: runId || "local",
    releaseChannel: resolveReleaseChannel(sourceRef),
    createdAt,
  };
}
