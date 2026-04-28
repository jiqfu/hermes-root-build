FROM ghcr.io/astral-sh/uv:0.11.6-python3.13-trixie AS uv_source
FROM tianon/gosu:1.19-trixie AS gosu_source
FROM debian:13.4

ARG UPSTREAM_SHA

ENV PYTHONUNBUFFERED=1
ENV PLAYWRIGHT_BROWSERS_PATH=/opt/hermes/.playwright

# Cache-friendly apt: preserves .deb packages across rebuilds via cache mount
RUN --mount=type=cache,target=/var/cache/apt,sharing=locked \
    --mount=type=cache,target=/var/lib/apt/lists,sharing=locked \
    apt-get update && \
    apt-get install -y --no-install-recommends \
        build-essential nodejs npm python3 ripgrep ffmpeg gcc python3-dev libffi-dev \
        procps git openssh-client docker-cli tini && \
    rm -rf /var/lib/apt/lists/*

RUN useradd -u 10000 -m -d /opt/data hermes

COPY --chmod=0755 --from=gosu_source /gosu /usr/local/bin/
COPY --chmod=0755 --from=uv_source /usr/local/bin/uv /usr/local/bin/uvx /usr/local/bin/

WORKDIR /opt/hermes

# UPSTREAM_SHA busts Docker cache: when a new upstream commit is detected,
# a different SHA is passed, forcing a re-clone instead of using stale cached layers
RUN echo "Upstream SHA: ${UPSTREAM_SHA:-unknown}" && \
    git clone --depth 1 --single-branch --branch main \
        https://github.com/NousResearch/hermes-agent.git /opt/hermes

# --mount=type=cache preserves npm tarball cache across SHA changes
# npm install still re-runs (layer busted by clone) but downloads hit local cache
RUN --mount=type=cache,target=/root/.npm \
    npm install --prefer-offline --no-audit && \
    npx playwright install --with-deps chromium --only-shell && \
    (cd web && npm install --prefer-offline --no-audit) && \
    (cd ui-tui && npm install --prefer-offline --no-audit) && \
    npm cache clean --force

# Parallel frontend builds
RUN (cd web && npm run build) & \
    (cd ui-tui && npm run build) & \
    wait

RUN chmod -R a+rX /opt/hermes

# --mount=type=cache preserves uv download cache across SHA changes
RUN --mount=type=cache,target=/root/.cache/uv \
    uv venv && \
    uv pip install --no-cache-dir -e ".[all]"

COPY --chmod=755 entrypoint.sh /opt/hermes/docker/entrypoint.sh

ENV HERMES_WEB_DIST=/opt/hermes/hermes_cli/web_dist
ENV HERMES_HOME=/opt/data
ENV PATH="/opt/data/.local/bin:${PATH}"
VOLUME [ "/opt/data" ]
ENTRYPOINT [ "/usr/bin/tini", "-g", "--", "/opt/hermes/docker/entrypoint.sh" ]
