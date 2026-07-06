import { mkdir, writeFile } from "node:fs/promises";

import { createBuildManifest } from "../src/pipelineStatus.js";

const manifest = createBuildManifest();

await mkdir("dist", { recursive: true });

await writeFile("dist/manifest.json", `${JSON.stringify(manifest, null, 2)}\n`);

await writeFile(
  "dist/index.html",
  `<!doctype html>
<html lang="en">
  <head>
    <meta charset="utf-8">
    <meta name="viewport" content="width=device-width, initial-scale=1">
    <title>GitHub Actions CI/CD Delivery Pipeline</title>
  </head>
  <body>
    <main>
      <h1>GitHub Actions CI/CD Delivery Pipeline</h1>
      <p>Build ${manifest.version} from ${manifest.refName} is ready for delivery.</p>
    </main>
  </body>
</html>
`,
);

console.log(`Built artifact ${manifest.version} for ${manifest.refName}`);
