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
