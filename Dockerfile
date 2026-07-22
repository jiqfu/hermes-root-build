FROM ghcr.io/astral-sh/uv:0.11.6-python3.13-trixie AS uv_source
FROM tianon/gosu:1.19-trixie AS gosu_source
FROM debian:13.4

ARG UPSTREAM_SHA

ENV PYTHONUNBUFFERED=1
ENV PLAYWRIGHT_BROWSERS_PATH=/opt/hermes/.playwright

# System deps
RUN --mount=type=cache,target=/var/cache/apt,sharing=locked \
    --mount=type=cache,target=/var/lib/apt/lists,sharing=locked \
    apt-get update && \
    apt-get install -y --no-install-recommends \
        ca-certificates curl python3 ripgrep ffmpeg gcc g++ make cmake \
        python3-dev python3-venv libffi-dev procps git openssh-client \
        docker-cli tini && \
    rm -rf /var/lib/apt/lists/*

RUN useradd -u 10000 -m -d /opt/data hermes

COPY --chmod=0755 --from=gosu_source /gosu /usr/local/bin/
COPY --chmod=0755 --from=uv_source /usr/local/bin/uv /usr/local/bin/uvx /usr/local/bin/

# ── Clone upstream (cache-busted by UPSTREAM_SHA) ──
# Delete apps/desktop so @playwright/test is not installed via workspace,
# matching official behavior where npx playwright downloads it on demand
RUN echo "${UPSTREAM_SHA:-unknown}" > /tmp/upstream-sha && \
    cd /tmp && rm -rf /opt/hermes && \
    git clone --depth 1 --single-branch --branch main \
        https://github.com/NousResearch/hermes-agent.git /opt/hermes && \
    rm -rf /opt/hermes/apps/desktop

WORKDIR /opt/hermes

# ── npm install + Playwright browsers ──
ENV npm_config_install_links=false
RUN --mount=type=cache,target=/root/.npm \
    npm install --prefer-offline --no-audit && \
    npx playwright install --with-deps chromium --only-shell && \
    npm cache clean --force

# ── Python deps ──
RUN touch ./README.md
RUN --mount=type=cache,target=/root/.cache/uv \
    uv sync --frozen --no-install-project --extra all

# ── Frontend builds ──
RUN cd web && npm run build && \
    cd ../ui-tui && npm run build

# ── Install Hermes itself ──
RUN uv pip install --no-cache-dir --no-deps -e "."

# ── Runtime config ──
COPY --chmod=755 entrypoint.sh /opt/hermes/docker/entrypoint.sh

ENV HERMES_WEB_DIST=/opt/hermes/hermes_cli/web_dist
ENV HERMES_HOME=/opt/data
ENV PATH="/opt/data/.local/bin:${PATH}"
VOLUME [ "/opt/data" ]
ENTRYPOINT [ "/usr/bin/tini", "-g", "--", "/opt/hermes/docker/entrypoint.sh" ]
