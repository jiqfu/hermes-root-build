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
        curl wget procps git openssh-client docker-cli tini && \
    rm -rf /var/lib/apt/lists/*

RUN useradd -u 10000 -m -d /opt/data hermes

COPY --chmod=0755 --from=gosu_source /gosu /usr/local/bin/
COPY --chmod=0755 --from=uv_source /usr/local/bin/uv /usr/local/bin/uvx /usr/local/bin/

WORKDIR /opt/hermes

# UPSTREAM_SHA busts Docker cache — write SHA to file so cache key tracks the value
RUN echo "${UPSTREAM_SHA:-unknown}" > /tmp/upstream-sha && \
    cd /tmp && rm -rf /opt/hermes && \
    git clone --depth 1 --single-branch --branch main \
        https://github.com/NousResearch/hermes-agent.git /opt/hermes

# Official upstream pattern: npm install + playwright + cache clean in one layer
RUN --mount=type=cache,target=/root/.npm \
    npm install --prefer-offline --no-audit && \
    npx playwright install --with-deps chromium --only-shell && \
    npm cache clean --force

# Parallel frontend builds
RUN (cd web && npm run build) & \
    (cd ui-tui && npm run build) & \
    wait

RUN chmod -R a+rX /opt/hermes

RUN --mount=type=cache,target=/root/.cache/uv \
    uv sync --frozen --no-install-project --extra all && \
    uv pip install --no-cache-dir --no-deps -e "."

COPY --chmod=755 entrypoint.sh /opt/hermes/docker/entrypoint.sh

ENV HERMES_WEB_DIST=/opt/hermes/hermes_cli/web_dist
ENV HERMES_HOME=/opt/data
ENV PATH="/opt/data/.local/bin:${PATH}"
VOLUME [ "/opt/data" ]
ENTRYPOINT [ "/usr/bin/tini", "-g", "--", "/opt/hermes/docker/entrypoint.sh" ]
