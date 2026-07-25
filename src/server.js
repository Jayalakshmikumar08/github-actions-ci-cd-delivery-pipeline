import { randomBytes } from "node:crypto";
import { createServer } from "node:http";
import { hostname } from "node:os";
import { pathToFileURL } from "node:url";

import { normalizeSha, resolveReleaseChannel } from "./pipelineStatus.js";

const strategyProfiles = {
  "blue-green": {
    accent: "#1684d6",
    label: "Blue / Green",
    mechanism: "Staging slot → preview → verify → atomic swap",
    platform: "Azure App Service",
    signal:
      "The serving release changes in one slot swap. A failed verification swaps the previous release back.",
  },
  canary: {
    accent: "#13a36f",
    label: "Canary",
    mechanism: "New revision → 5% → 25% → 50% → 100%",
    platform: "Azure Container Apps",
    signal:
      "Repeated observations can alternate between stable and candidate releases while weighted traffic is active.",
  },
  rolling: {
    accent: "#7a55c7",
    label: "Rolling Update",
    mechanism: "Four pods · maxSurge 1 · maxUnavailable 0",
    platform: "Azure Kubernetes Service",
    signal:
      "Serving pod IDs change progressively while readiness probes keep available capacity in service.",
  },
  local: {
    accent: "#64748b",
    label: "Local verification",
    mechanism: "No Azure deployment strategy is active",
    platform: "Local Node.js",
    signal:
      "Deploy through one of the strategy workflows to observe live promotion behavior.",
  },
};

function selectStrategy(value) {
  const key = String(value || "local").toLowerCase();
  return Object.hasOwn(strategyProfiles, key) ? key : "local";
}

function escapeHtml(value) {
  const entities = {
    "&": "&amp;",
    "<": "&lt;",
    ">": "&gt;",
    '"': "&quot;",
    "'": "&#39;",
  };
  return String(value).replace(/[&<>"']/g, (character) => entities[character]);
}

function renderDashboard(metadata, profile, nonce) {
  const safe = Object.fromEntries(
    Object.entries(metadata).map(([key, value]) => [key, escapeHtml(value)]),
  );
  const initialMetadata = JSON.stringify(metadata).replaceAll("<", "\\u003c");

  return `<!doctype html>
<html lang="en">
  <head>
    <meta charset="utf-8">
    <meta name="viewport" content="width=device-width, initial-scale=1">
    <meta name="color-scheme" content="dark">
    <title>${safe.strategyLabel} · Azure delivery lab</title>
    <style nonce="${nonce}">
      :root { --accent: ${profile.accent}; --ink: #ecf7ff; --muted: #a8c4d8; }
      * { box-sizing: border-box; }
      body { margin: 0; min-height: 100vh; color: var(--ink); background: radial-gradient(circle at 12% 8%, #164b70, transparent 38%), #071827; font: 16px/1.5 Inter, "Segoe UI", sans-serif; }
      main { width: min(1100px, calc(100% - 32px)); margin: 0 auto; padding: 48px 0 64px; }
      .eyebrow { color: #80cfff; font-size: .78rem; font-weight: 800; letter-spacing: .16em; text-transform: uppercase; }
      h1 { margin: 8px 0 4px; font-size: clamp(2.3rem, 7vw, 5.6rem); line-height: 1; }
      .lead { margin: 0 0 32px; color: var(--muted); font-size: 1.1rem; }
      .strategy { color: var(--accent); }
      .grid { display: grid; grid-template-columns: repeat(12, 1fr); gap: 16px; }
      .card { border: 1px solid #ffffff1c; border-radius: 18px; padding: 22px; background: #0c2639cc; box-shadow: 0 18px 48px #00101f66; }
      .hero { grid-column: span 8; border-top: 4px solid var(--accent); }
      .stage { grid-column: span 4; }
      .wide { grid-column: span 12; }
      .metric { margin: 4px 0; font: 700 clamp(1.25rem, 3vw, 2rem) ui-monospace, SFMono-Regular, Consolas, monospace; overflow-wrap: anywhere; }
      .label { color: var(--muted); font-size: .74rem; font-weight: 800; letter-spacing: .13em; text-transform: uppercase; }
      .pill { display: inline-flex; align-items: center; gap: 8px; margin-top: 16px; border: 1px solid #ffffff2b; border-radius: 999px; padding: 8px 13px; background: #ffffff0b; }
      .dot { width: 9px; height: 9px; border-radius: 50%; background: #3ce69a; box-shadow: 0 0 18px #3ce69a; }
      .flow { margin-top: 12px; color: #fff; font-size: 1.15rem; font-weight: 700; }
      .observations { display: flex; flex-wrap: wrap; gap: 9px; margin-top: 14px; min-height: 42px; }
      .observation { border-left: 4px solid var(--accent); border-radius: 8px; padding: 8px 10px; background: #071827; font: .75rem ui-monospace, SFMono-Regular, Consolas, monospace; }
      footer { margin-top: 22px; color: var(--muted); font-size: .82rem; }
      code { color: #d6f0ff; }
      @media (max-width: 760px) { .hero, .stage, .wide { grid-column: span 12; } main { padding-top: 28px; } }
    </style>
  </head>
  <body>
    <main>
      <div class="eyebrow">Live Azure deployment strategy lab</div>
      <h1><span class="strategy">${safe.strategyLabel}</span></h1>
      <p class="lead">${safe.platform} · real public traffic · automatic health verification and rollback</p>
      <section class="grid" aria-label="Live deployment metadata">
        <article class="card hero">
          <div class="label">What this deployment is doing</div>
          <div class="flow">${escapeHtml(profile.mechanism)}</div>
          <p>${escapeHtml(profile.signal)}</p>
          <div class="pill"><span class="dot"></span><span id="status">Ready and serving traffic</span></div>
        </article>
        <article class="card stage">
          <div class="label">Lifecycle stage</div>
          <div class="metric" id="stage">${safe.stage.toUpperCase()}</div>
          <div class="label">Release channel</div>
          <div>${safe.releaseChannel}</div>
        </article>
        <article class="card hero">
          <div class="label">Release SHA currently serving this request</div>
          <div class="metric" id="release">${safe.releaseSha}</div>
        </article>
        <article class="card stage">
          <div class="label">Serving instance / revision</div>
          <div class="metric" id="instance">${safe.instanceId}</div>
        </article>
        <article class="card wide">
          <div class="label">Live traffic observations · refreshes every 2 seconds</div>
          <p>Watch release and instance values. Canary can show mixed releases; rolling shows pods changing progressively; blue/green switches the release as one unit.</p>
          <div class="observations" id="observations" aria-live="polite"></div>
        </article>
      </section>
      <footer>Machine-readable endpoints: <code>/deployment</code>, <code>/version</code>, <code>/health/live</code>, <code>/health/ready</code></footer>
    </main>
    <script nonce="${nonce}">
      const observations = document.querySelector("#observations");
      let current = ${initialMetadata};
      function render(value) {
        document.querySelector("#release").textContent = value.releaseSha;
        document.querySelector("#instance").textContent = value.instanceId;
        document.querySelector("#stage").textContent = value.stage.toUpperCase();
        const item = document.createElement("div");
        item.className = "observation";
        item.textContent = new Date().toLocaleTimeString() + " · " + value.releaseSha + " · " + value.instanceId;
        observations.prepend(item);
        while (observations.children.length > 8) observations.lastElementChild.remove();
      }
      async function observe() {
        try {
          const response = await fetch("/deployment", { cache: "no-store" });
          if (!response.ok) throw new Error("HTTP " + response.status);
          current = await response.json();
          document.querySelector("#status").textContent = "Ready and serving traffic";
          render(current);
        } catch {
          document.querySelector("#status").textContent = "Observation failed; retrying";
        }
      }
      render(current);
      setInterval(observe, 2000);
    </script>
  </body>
</html>`;
}

export function createApplication({
  releaseSha = process.env.RELEASE_SHA,
  deploymentStrategy = process.env.DEPLOYMENT_STRATEGY,
  deploymentStage = process.env.DEPLOYMENT_STAGE,
  instanceId = process.env.CONTAINER_APP_REVISION ||
    process.env.WEBSITE_INSTANCE_ID ||
    process.env.HOSTNAME ||
    hostname(),
  port = Number(process.env.PORT || 8080),
} = {}) {
  const version = normalizeSha(releaseSha);
  const strategy = selectStrategy(deploymentStrategy);
  const profile = strategyProfiles[strategy];
  const startedAt = new Date().toISOString();
  let shuttingDown = false;

  function deploymentMetadata() {
    return {
      application: "github-actions-ci-cd-delivery-pipeline",
      instanceId: String(instanceId || "unknown").slice(0, 32),
      platform: profile.platform,
      releaseChannel: resolveReleaseChannel(
        process.env.GITHUB_REF_NAME || "main",
      ),
      releaseSha: version,
      stage: String(deploymentStage || "local").toLowerCase(),
      startedAt,
      strategy,
      strategyLabel: profile.label,
    };
  }

  const server = createServer((request, response) => {
    const metadata = deploymentMetadata();
    response.setHeader("Cache-Control", "no-store");
    response.setHeader("Content-Type", "application/json; charset=utf-8");
    response.setHeader(
      "Permissions-Policy",
      "camera=(), geolocation=(), microphone=()",
    );
    response.setHeader("Referrer-Policy", "no-referrer");
    response.setHeader("X-Content-Type-Options", "nosniff");
    response.setHeader("X-Frame-Options", "DENY");
    response.setHeader("X-Deployment-Strategy", metadata.strategy);
    response.setHeader("X-Release-Sha", metadata.releaseSha);
    response.setHeader("X-Serving-Instance", metadata.instanceId);

    if (request.url === "/health/live") {
      response.writeHead(200).end(JSON.stringify({ status: "live" }));
      return;
    }

    if (request.url === "/health/ready") {
      const status = shuttingDown ? 503 : 200;
      response.writeHead(status).end(
        JSON.stringify({
          status: shuttingDown ? "draining" : "ready",
          releaseSha: version,
        }),
      );
      return;
    }

    if (request.url === "/deployment" || request.url === "/version") {
      response.writeHead(200).end(JSON.stringify(metadata));
      return;
    }

    if (request.url === "/") {
      const nonce = randomBytes(18).toString("base64");
      response.setHeader(
        "Content-Security-Policy",
        `default-src 'none'; connect-src 'self'; style-src 'nonce-${nonce}'; script-src 'nonce-${nonce}'; base-uri 'none'; form-action 'none'; frame-ancestors 'none'`,
      );
      response.setHeader("Content-Type", "text/html; charset=utf-8");
      response.writeHead(200).end(renderDashboard(metadata, profile, nonce));
      return;
    }

    response.writeHead(404).end(JSON.stringify({ error: "not found" }));
  });

  function drain() {
    shuttingDown = true;
    server.close();
  }

  return { server, port, drain };
}

if (
  process.argv[1] &&
  import.meta.url === pathToFileURL(process.argv[1]).href
) {
  const { server, port, drain } = createApplication();
  server.listen(port, "0.0.0.0", () => {
    console.log(`Application listening on port ${port}`);
  });
  process.on("SIGTERM", drain);
  process.on("SIGINT", drain);
}
