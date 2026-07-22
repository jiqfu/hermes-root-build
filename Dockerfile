1|FROM ghcr.io/astral-sh/uv:0.11.6-python3.13-trixie AS uv_source
2|FROM tianon/gosu:1.19-trixie AS gosu_source
3|FROM debian:13.4
4|
5|ARG UPSTREAM_SHA
6|
7|ENV PYTHONUNBUFFERED=1
8|ENV PLAYWRIGHT_BROWSERS_PATH=/opt/hermes/.playwright
9|
10|# Cache-friendly apt: preserves .deb packages across rebuilds via cache mount
11|RUN --mount=type=cache,target=/var/cache/apt,sharing=locked \
12|    --mount=type=cache,target=/var/lib/apt/lists,sharing=locked \
13|    apt-get update && \
14|    apt-get install -y --no-install-recommends \
15|        build-essential nodejs npm python3 ripgrep ffmpeg gcc python3-dev libffi-dev \
16|        curl wget procps git openssh-client docker-cli tini && \
17|    rm -rf /var/lib/apt/lists/*
18|
19|RUN useradd -u 10000 -m -d /opt/data hermes
20|
21|COPY --chmod=0755 --from=gosu_source /gosu /usr/local/bin/
22|COPY --chmod=0755 --from=uv_source /usr/local/bin/uv /usr/local/bin/uvx /usr/local/bin/
23|
24|WORKDIR /opt/hermes
25|
26|# UPSTREAM_SHA busts Docker cache: when a new upstream commit is detected,
27|# a different SHA is passed, forcing a re-clone instead of using stale cached layers
28|# Writing SHA to a file ensures Docker cache key includes the actual value
29|RUN echo "${UPSTREAM_SHA:-unknown}" > /tmp/upstream-sha && \
30|    rm -rf /opt/hermes && \
31|    git clone --depth 1 --single-branch --branch main \
32|        https://github.com/NousResearch/hermes-agent.git /opt/hermes
33|
34|# Verify toolchain + install root workspace deps
35|RUN --mount=type=cache,target=/root/.npm \
36|    node --version && npm --version && npx --version && \
37|    npm install --prefer-offline --no-audit
38|
39|# Install Playwright browser shell (for browser tool support)
40|RUN --mount=type=cache,target=/root/.npm \
41|    npx playwright install --with-deps chromium --only-shell && \
42|    npm cache clean --force
43|
44|# Parallel frontend builds
45|RUN (cd web && npm run build) & \
46|    (cd ui-tui && npm run build) & \
47|    wait
48|
49|RUN chmod -R a+rX /opt/hermes
50|
51|# Use uv sync --frozen (matching upstream approach) so dependency versions
52|# are resolved from the pinned uv.lock file shipped with the source.
53|# uv pip install -e ".[all]" does fresh resolution and can fail when
54|# packages like mistralai become temporarily unreachable on PyPI;
55|# uv sync --frozen uses lock file entries which were valid at lock time.
56|RUN --mount=type=cache,target=/root/.cache/uv \
57|    uv sync --frozen --no-install-project --extra all && \
58|    uv pip install --no-cache-dir --no-deps -e "."
59|
60|COPY --chmod=755 entrypoint.sh /opt/hermes/docker/entrypoint.sh
61|
62|ENV HERMES_WEB_DIST=/opt/hermes/hermes_cli/web_dist
63|ENV HERMES_HOME=/opt/data
64|ENV PATH="/opt/data/.local/bin:${PATH}"
65|VOLUME [ "/opt/data" ]
66|ENTRYPOINT [ "/usr/bin/tini", "-g", "--", "/opt/hermes/docker/entrypoint.sh" ]
67|