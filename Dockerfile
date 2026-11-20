# syntax=docker/dockerfile:1.7

# The digest is the linux/amd64 manifest for node:24-bookworm-slim, inspected
# on 2026-11-20. The build command and release workflow select linux/amd64.
FROM node:24-bookworm-slim@sha256:0e2646ab57e77b7a384a0cb59b6815b182c77e1f9c3ba36bd8435bd9c4e6680e AS runtime

ARG PLAYWRIGHT_NODE_VERSION=1.65.1
ARG PLAYWRIGHT_PYTHON_VERSION=1.65.2
ARG RUNTIME_VERSION=1.65.2-r1
ARG SOURCE_COMMIT=local

ENV DEBIAN_FRONTEND=noninteractive \
    PLAYWRIGHT_BROWSERS_PATH=/ms-playwright \
    PLAYWRIGHT_RUNTIME_CHROMIUM_VERSION=159.0.8154.6 \
    PYTHONDONTWRITEBYTECODE=1 \
    PYTHONUNBUFFERED=1

RUN set -eux; \
    test "$(dpkg --print-architecture)" = amd64; \
    apt-get update; \
    apt-get install -y --no-install-recommends \
        ca-certificates \
        libatomic1 \
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
    npm install --no-save --ignore-scripts --no-audit --fund=false "playwright@${PLAYWRIGHT_NODE_VERSION}"; \
    test "${PLAYWRIGHT_NODE_VERSION}" = 1.65.1; \
    test "${PLAYWRIGHT_PYTHON_VERSION}" = 1.65.2; \
    npx --no-install playwright install-deps chromium; \
    npx --no-install playwright install ffmpeg; \
    rm -rf "${temp_dir}" /root/.npm /root/.cache; \
    rm -rf /var/cache/apt/* /var/lib/apt/lists/*

RUN set -eux; \
    temp_dir="$(mktemp -d)"; \
    cd "${temp_dir}"; \
    wget -q "https://storage.googleapis.com/chrome-for-testing-public/${PLAYWRIGHT_RUNTIME_CHROMIUM_VERSION}/linux64/chrome-linux64.zip"; \
    wget -q "https://storage.googleapis.com/chrome-for-testing-public/${PLAYWRIGHT_RUNTIME_CHROMIUM_VERSION}/linux64/chrome-headless-shell-linux64.zip"; \
    echo '370601106c1b5619aae5f06f7a3fdc60836486135934779461e2a208d777f596  chrome-linux64.zip' | sha256sum -c -; \
    echo '77a6442fd3c8acd3bef9e1067fc26f5ef464277d22f0e8cb58dc3e4077a3e458  chrome-headless-shell-linux64.zip' | sha256sum -c -; \
    mkdir -p "${PLAYWRIGHT_BROWSERS_PATH}/chromium-1255" "${PLAYWRIGHT_BROWSERS_PATH}/chromium_headless_shell-1255"; \
    unzip -q chrome-linux64.zip -d "${PLAYWRIGHT_BROWSERS_PATH}/chromium-1255"; \
    unzip -q chrome-headless-shell-linux64.zip -d "${PLAYWRIGHT_BROWSERS_PATH}/chromium_headless_shell-1255"; \
    test "$("${PLAYWRIGHT_BROWSERS_PATH}/chromium-1255/chrome-linux64/chrome" --version | awk '{print $NF}')" = "${PLAYWRIGHT_RUNTIME_CHROMIUM_VERSION}"; \
    test "$("${PLAYWRIGHT_BROWSERS_PATH}/chromium_headless_shell-1255/chrome-headless-shell-linux64/chrome-headless-shell" --version | awk '{print $NF}')" = "${PLAYWRIGHT_RUNTIME_CHROMIUM_VERSION}"; \
    touch "${PLAYWRIGHT_BROWSERS_PATH}/chromium-1255/INSTALLATION_COMPLETE" "${PLAYWRIGHT_BROWSERS_PATH}/chromium_headless_shell-1255/INSTALLATION_COMPLETE"; \
    ln -s "${PLAYWRIGHT_BROWSERS_PATH}/chromium-1255" "${PLAYWRIGHT_BROWSERS_PATH}/chromium-1254"; \
    ln -s "${PLAYWRIGHT_BROWSERS_PATH}/chromium_headless_shell-1255" "${PLAYWRIGHT_BROWSERS_PATH}/chromium_headless_shell-1254"; \
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
    PLAYWRIGHT_RUNTIME_PLAYWRIGHT_VERSION=${PLAYWRIGHT_PYTHON_VERSION} \
    PLAYWRIGHT_RUNTIME_PLAYWRIGHT_NODE_VERSION=${PLAYWRIGHT_NODE_VERSION} \
    PLAYWRIGHT_RUNTIME_PLAYWRIGHT_PYTHON_VERSION=${PLAYWRIGHT_PYTHON_VERSION}

LABEL org.opencontainers.image.title="Playwright Chromium Runtime" \
      org.opencontainers.image.description="Shared Node 24 and Python 3.11 runtime with Playwright Chromium browser artifacts" \
      org.opencontainers.image.source="https://github.com/j2h4u/playwright-chromium-runtime" \
      org.opencontainers.image.url="https://github.com/j2h4u/playwright-chromium-runtime" \
      org.opencontainers.image.licenses="MIT" \
      org.opencontainers.image.version="${RUNTIME_VERSION}" \
      org.opencontainers.image.revision="${SOURCE_COMMIT}" \
      com.j2h4u.runtime.name="playwright-chromium-runtime" \
      com.j2h4u.runtime.version="${RUNTIME_VERSION}" \
      com.j2h4u.playwright.version="${PLAYWRIGHT_PYTHON_VERSION}" \
      com.j2h4u.playwright.node.version="${PLAYWRIGHT_NODE_VERSION}" \
      com.j2h4u.playwright.python.version="${PLAYWRIGHT_PYTHON_VERSION}" \
      com.j2h4u.chromium.version="${PLAYWRIGHT_RUNTIME_CHROMIUM_VERSION}" \
      com.j2h4u.chromium.source="https://googlechromelabs.github.io/chrome-for-testing/"

# The smoke stage is intentionally excluded from the default image. It adds
# client bindings only to validate this runtime during a disposable build.
FROM runtime AS smoke

ARG PLAYWRIGHT_NODE_VERSION
ARG PLAYWRIGHT_PYTHON_VERSION

COPY smoke/ /opt/playwright-runtime-smoke/

RUN set -eux; \
    node_dir="$(mktemp -d)"; \
    cd "${node_dir}"; \
    npm init --yes >/dev/null; \
    npm install --no-save --ignore-scripts --no-audit --fund=false "playwright@${PLAYWRIGHT_NODE_VERSION}"; \
    NODE_PATH="${node_dir}/node_modules" PLAYWRIGHT_BROWSERS_PATH="${PLAYWRIGHT_BROWSERS_PATH}" node /opt/playwright-runtime-smoke/node-smoke.cjs; \
    python_dir="$(mktemp -d)"; \
    python3 -m venv "${python_dir}"; \
    "${python_dir}/bin/pip" install --no-cache-dir "playwright==${PLAYWRIGHT_PYTHON_VERSION}"; \
    PLAYWRIGHT_BROWSERS_PATH="${PLAYWRIGHT_BROWSERS_PATH}" xvfb-run -a -s '-screen 0 1280x720x24' "${python_dir}/bin/python" /opt/playwright-runtime-smoke/python-smoke.py; \
    rm -rf "${node_dir}" "${python_dir}" /opt/playwright-runtime-smoke /root/.npm /root/.cache
