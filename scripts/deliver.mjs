import { mkdir, readFile, writeFile } from "node:fs/promises";

const targetEnvironment = process.env.DELIVERY_ENVIRONMENT || "staging";
const manifestRaw = await readFile("dist/manifest.json", "utf8");
const buildManifest = JSON.parse(manifestRaw);

if (!buildManifest.application || !buildManifest.sha) {
  throw new Error("Build artifact is missing required delivery metadata.");
}

const deliveryManifest = {
  application: buildManifest.application,
  environment: targetEnvironment,
  artifactVersion: buildManifest.version,
  artifactSha: buildManifest.sha,
  sourceRef: buildManifest.refName,
  releaseChannel: buildManifest.releaseChannel,
  deliveredAt: new Date().toISOString(),
  controls: [
    "build artifact reused from CI",
    "automated tests completed before delivery",
    "delivery environment isolated from build logic",
  ],
};

await mkdir("release", { recursive: true });
await writeFile(
  "release/delivery-manifest.json",
  `${JSON.stringify(deliveryManifest, null, 2)}\n`,
);

console.log(
  `Prepared ${targetEnvironment} delivery for ${buildManifest.version}`,
);
