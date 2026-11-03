# Playwright Chromium Runtime

Small shared `linux/amd64` image for the Ozon MCP server and Google Meet Companion. It provides Node 24, Python 3.11 with venv support, Xvfb plus xauth, wget, Playwright 1.64.1 FFmpeg, and Chrome for Testing 156.0.8078.80 headed and headless browser payloads. Firefox and WebKit are not installed.

The browser is a security override of the older Chromium bundled with Playwright 1.64.1. The official Chrome for Testing archives are downloaded from `chrome-for-testing-public` and verified by pinned SHA-256 in the Dockerfile. Their payloads occupy Playwright's revision 1248 paths; the unpatched Playwright Chromium is never installed. The override must be reviewed together with each Playwright upgrade, including its revision and both archive hashes.

Do not run `playwright install` against `/ms-playwright` in a consumer: Playwright's browser garbage collection can remove the runtime-managed payload or replace it with its older bundled browser. Consumers must use the inherited payload unchanged.

The image is based on the verified amd64 `node:24-bookworm-slim` digest recorded in the Dockerfile. It is currently tested and published for `linux/amd64`; other architectures are outside the release contract.

## Local build and smoke test

Run these commands from the repository root:

```bash
docker build --platform linux/amd64 \
  --build-arg PLAYWRIGHT_VERSION=1.64.1 \
  --build-arg RUNTIME_VERSION=1.64.1-r1 \
  -t playwright-chromium-runtime:local .

docker build --platform linux/amd64 --target smoke \
  --build-arg PLAYWRIGHT_VERSION=1.64.1 \
  --build-arg RUNTIME_VERSION=1.64.1-r1 \
  -t playwright-chromium-runtime:smoke .
```

The smoke target installs the matching Node and Python Playwright bindings in temporary build directories, launches headless Chromium from Node, and launches headed Chromium through Xvfb from Python. Those bindings and all package caches are removed from the default image. The final image exposes `/ms-playwright` readably and executably to arbitrary child users.

To update Playwright, review the browser override and matching revision, change the default `PLAYWRIGHT_VERSION` argument and workflow defaults, set a new runtime release, run both builds above, and inspect the resulting labels and `/ms-playwright` directories. A base or security rebuild with the same Playwright uses the next runtime revision. Every release must pass both smoke launches before publication.

## Consumer contract

Consumers install their own application dependencies and matching Playwright 1.64.1 client binding in their own dependency environment, set `PLAYWRIGHT_BROWSERS_PATH=/ms-playwright`, and create their own runtime user. The image exposes `PLAYWRIGHT_RUNTIME_VERSION`, `PLAYWRIGHT_RUNTIME_PLAYWRIGHT_VERSION`, and `PLAYWRIGHT_RUNTIME_CHROMIUM_VERSION` for binding and browser version checks. The Node consumer uses the Node 24 runtime; the Python consumer creates a Python 3.11 venv and supplies `DISPLAY` through its own Xvfb setup when headed Chromium is required. Consumers must pin the published image by digest, for example:

```dockerfile
FROM ghcr.io/j2h4u/playwright-chromium-runtime@sha256:<published-digest>
```

The runtime repository owns the base image pin, OS browser dependencies, Playwright browser payloads, labels, and release workflow. Consumer repositories own application code, client bindings, users, profiles, environment configuration, and process entrypoints. No local prebuilt image tag is required for GHCR publication; the release workflow builds directly from the checked out commit.

## Release workflow

Pull requests build the amd64 image and run both smoke launches. Release tags use the immutable `v<playwright-version>-r<runtime-revision>` form, such as `v1.64.1-r1`; a manually dispatched workflow accepts the same runtime version form. Both publish `ghcr.io/j2h4u/playwright-chromium-runtime`. The publish job has package write permission only; the build job uses Buildx GitHub Actions cache and does not push.
