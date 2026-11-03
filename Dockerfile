# syntax=docker/dockerfile:1.7

# The digest is the linux/amd64 manifest for node:24-bookworm-slim, inspected
# on 2026-09-09. The build command and release workflow select linux/amd64.
FROM node:24-bookworm-slim@sha256:6642ef280aebc09c4541bee0b15c9f89f0f3f3c247ddee79ae1d37eddfdcbbaa AS runtime

ARG PLAYWRIGHT_VERSION=1.64.1
ARG RUNTIME_VERSION=1.64.1-r1
ARG SOURCE_COMMIT=local

ENV DEBIAN_FRONTEND=noninteractive \
    PLAYWRIGHT_BROWSERS_PATH=/ms-playwright \
    PLAYWRIGHT_RUNTIME_CHROMIUM_VERSION=156.0.8078.80 \
    PYTHONDONTWRITEBYTECODE=1 \
    PYTHONUNBUFFERED=1

RUN set -eux; \
    test "$(dpkg --print-architecture)" = amd64; \
    apt-get update; \
    apt-get install -y --no-install-recommends \
        ca-certificates \
        python3.11 \
        python3.11-venv \
        unzip \
        wget \
        xauth \
        xvfb; \
    mkdir -p "${PLAYWRIGHT_BROWSERS_PATH}"; \
    temp_dir="$(mktemp -d)"; \
    cd "${temp_dir}"; \
    npm init --yes >/dev/null; \
    npm install --no-save --ignore-scripts --no-audit --fund=false "playwright@${PLAYWRIGHT_VERSION}"; \
    test "${PLAYWRIGHT_VERSION}" = 1.64.1; \
    npx --no-install playwright install-deps chromium; \
    npx --no-install playwright install ffmpeg; \
    rm -rf "${temp_dir}" /root/.npm /root/.cache; \
    rm -rf /var/cache/apt/* /var/lib/apt/lists/*

RUN set -eux; \
    temp_dir="$(mktemp -d)"; \
    cd "${temp_dir}"; \
    wget -q "https://storage.googleapis.com/chrome-for-testing-public/${PLAYWRIGHT_RUNTIME_CHROMIUM_VERSION}/linux64/chrome-linux64.zip"; \
    wget -q "https://storage.googleapis.com/chrome-for-testing-public/${PLAYWRIGHT_RUNTIME_CHROMIUM_VERSION}/linux64/chrome-headless-shell-linux64.zip"; \
    echo 'b711c720f774be355197f32edf37e0651418ba036d92446ee2da19ac017540a7  chrome-linux64.zip' | sha256sum -c -; \
    echo '547dcd374e02961bf998f6046a267644f8502225c36bb78ca307dab32a0b3eb4  chrome-headless-shell-linux64.zip' | sha256sum -c -; \
    mkdir -p "${PLAYWRIGHT_BROWSERS_PATH}/chromium-1248" "${PLAYWRIGHT_BROWSERS_PATH}/chromium_headless_shell-1248"; \
    unzip -q chrome-linux64.zip -d "${PLAYWRIGHT_BROWSERS_PATH}/chromium-1248"; \
    unzip -q chrome-headless-shell-linux64.zip -d "${PLAYWRIGHT_BROWSERS_PATH}/chromium_headless_shell-1248"; \
    test "$("${PLAYWRIGHT_BROWSERS_PATH}/chromium-1248/chrome-linux64/chrome" --version | awk '{print $NF}')" = "${PLAYWRIGHT_RUNTIME_CHROMIUM_VERSION}"; \
    test "$("${PLAYWRIGHT_BROWSERS_PATH}/chromium_headless_shell-1248/chrome-headless-shell-linux64/chrome-headless-shell" --version | awk '{print $NF}')" = "${PLAYWRIGHT_RUNTIME_CHROMIUM_VERSION}"; \
    touch "${PLAYWRIGHT_BROWSERS_PATH}/chromium-1248/INSTALLATION_COMPLETE" "${PLAYWRIGHT_BROWSERS_PATH}/chromium_headless_shell-1248/INSTALLATION_COMPLETE"; \
    find "${PLAYWRIGHT_BROWSERS_PATH}" -mindepth 1 -maxdepth 1 -type d -printf '%f\n' | sort > /tmp/playwright-browser-dirs; \
    test "$(grep -Ec '^chromium-[0-9]+$' /tmp/playwright-browser-dirs)" -eq 1; \
    test "$(grep -Ec '^chromium_headless_shell-[0-9]+$' /tmp/playwright-browser-dirs)" -eq 1; \
    test "$(grep -Ec '^ffmpeg-[0-9]+$' /tmp/playwright-browser-dirs)" -eq 1; \
    if grep -Evq '^(\.links|chromium-[0-9]+|chromium_headless_shell-[0-9]+|ffmpeg-[0-9]+)$' /tmp/playwright-browser-dirs; then \
        echo 'unexpected Playwright browser directory' >&2; \
        cat /tmp/playwright-browser-dirs >&2; \
        exit 1; \
    fi; \
    chmod -R a+rX "${PLAYWRIGHT_BROWSERS_PATH}"; \
    rm -rf "${temp_dir}" /tmp/playwright-browser-dirs /root/.npm /root/.cache; \
    rm -rf /var/cache/apt/* /var/lib/apt/lists/*

# Release metadata stays below the expensive browser layer so a new source
# commit or runtime revision does not invalidate the browser cache.
ENV PLAYWRIGHT_RUNTIME_VERSION=${RUNTIME_VERSION} \
    PLAYWRIGHT_RUNTIME_PLAYWRIGHT_VERSION=${PLAYWRIGHT_VERSION}

LABEL org.opencontainers.image.title="Playwright Chromium Runtime" \
      org.opencontainers.image.description="Shared Node 24 and Python 3.11 runtime with Playwright Chromium browser artifacts" \
      org.opencontainers.image.source="https://github.com/j2h4u/playwright-chromium-runtime" \
      org.opencontainers.image.url="https://github.com/j2h4u/playwright-chromium-runtime" \
      org.opencontainers.image.licenses="MIT" \
      org.opencontainers.image.version="${RUNTIME_VERSION}" \
      org.opencontainers.image.revision="${SOURCE_COMMIT}" \
      com.j2h4u.runtime.name="playwright-chromium-runtime" \
      com.j2h4u.runtime.version="${RUNTIME_VERSION}" \
      com.j2h4u.playwright.version="${PLAYWRIGHT_VERSION}" \
      com.j2h4u.chromium.version="${PLAYWRIGHT_RUNTIME_CHROMIUM_VERSION}" \
      com.j2h4u.chromium.source="https://googlechromelabs.github.io/chrome-for-testing/"

# The smoke stage is intentionally excluded from the default image. It adds
# client bindings only to validate this runtime during a disposable build.
FROM runtime AS smoke

ARG PLAYWRIGHT_VERSION

COPY smoke/ /opt/playwright-runtime-smoke/

RUN set -eux; \
    node_dir="$(mktemp -d)"; \
    cd "${node_dir}"; \
    npm init --yes >/dev/null; \
    npm install --no-save --ignore-scripts --no-audit --fund=false "playwright@${PLAYWRIGHT_VERSION}"; \
    NODE_PATH="${node_dir}/node_modules" PLAYWRIGHT_BROWSERS_PATH="${PLAYWRIGHT_BROWSERS_PATH}" node /opt/playwright-runtime-smoke/node-smoke.cjs; \
    python_dir="$(mktemp -d)"; \
    python3 -m venv "${python_dir}"; \
    "${python_dir}/bin/pip" install --no-cache-dir "playwright==${PLAYWRIGHT_VERSION}"; \
    PLAYWRIGHT_BROWSERS_PATH="${PLAYWRIGHT_BROWSERS_PATH}" xvfb-run -a -s '-screen 0 1280x720x24' "${python_dir}/bin/python" /opt/playwright-runtime-smoke/python-smoke.py; \
    rm -rf "${node_dir}" "${python_dir}" /opt/playwright-runtime-smoke /root/.npm /root/.cache
