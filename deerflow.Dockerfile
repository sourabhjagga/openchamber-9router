# syntax=docker/dockerfile:1
# =============================================================================
# DeerFlow — built from source (ARM64 + AMD64 compatible)
# Mirrors the official bytedance/deer-flow build pattern exactly.
# =============================================================================

# ── Stage 0: uv binary ───────────────────────────────────────────────────────
FROM ghcr.io/astral-sh/uv:0.7.20 AS uv-source

# ── Stage 1: Clone source ────────────────────────────────────────────────────
FROM alpine/git:latest AS source
WORKDIR /src
ARG CACHE_BUST_DEERFLOW=1
RUN git clone --depth 1 https://github.com/bytedance/deer-flow.git .

# ── Stage 2: Python backend builder ──────────────────────────────────────────
FROM python:3.12-slim-bookworm AS backend-builder

ARG NODE_MAJOR=22
COPY --from=uv-source /uv /uvx /usr/local/bin/

RUN apt-get update && apt-get install -y \
    curl build-essential gnupg ca-certificates \
    && mkdir -p /etc/apt/keyrings \
    && curl -fsSL https://deb.nodesource.com/gpgkey/nodesource-repo.gpg.key \
       | gpg --dearmor -o /etc/apt/keyrings/nodesource.gpg \
    && echo "deb [signed-by=/etc/apt/keyrings/nodesource.gpg] https://deb.nodesource.com/node_${NODE_MAJOR}.x nodistro main" \
       > /etc/apt/sources.list.d/nodesource.list \
    && apt-get update && apt-get install -y nodejs \
    && rm -rf /var/lib/apt/lists/*

WORKDIR /app
COPY --from=source /src/backend ./backend

RUN --mount=type=cache,target=/root/.cache/uv \
    cd backend && uv sync

# ── Stage 3: Frontend builder ─────────────────────────────────────────────────
FROM node:22-alpine AS frontend-builder

RUN corepack enable && corepack install -g pnpm@10.26.2

WORKDIR /app
COPY --from=source /src/frontend ./frontend

RUN cd /app/frontend && pnpm install --frozen-lockfile
# SKIP_ENV_VALIDATION=1: BETTER_AUTH_SECRET is injected at runtime, not build time
RUN cd /app/frontend && SKIP_ENV_VALIDATION=1 pnpm build

# ── Stage 4: Runtime ─────────────────────────────────────────────────────────
FROM python:3.12-slim-bookworm AS runtime

ENV LANG=C.UTF-8
ENV LC_ALL=C.UTF-8
ENV PYTHONIOENCODING=utf-8

COPY --from=uv-source /uv /uvx /usr/local/bin/

# Install Node.js in runtime image properly (not just copying binaries)
RUN apt-get update && apt-get install -y curl gnupg ca-certificates \
    && mkdir -p /etc/apt/keyrings \
    && curl -fsSL https://deb.nodesource.com/gpgkey/nodesource-repo.gpg.key \
       | gpg --dearmor -o /etc/apt/keyrings/nodesource.gpg \
    && echo "deb [signed-by=/etc/apt/keyrings/nodesource.gpg] https://deb.nodesource.com/node_22.x nodistro main" \
       > /etc/apt/sources.list.d/nodesource.list \
    && apt-get update && apt-get install -y nodejs \
    && rm -rf /var/lib/apt/lists/*

# Install pnpm in runtime so 'pnpm start' works
RUN corepack enable && corepack install -g pnpm@10.26.2

WORKDIR /app

# Backend with pre-built venv
COPY --from=backend-builder /app/backend ./backend

# Skills and default configs
COPY --from=source /src/skills ./skills
COPY --from=source /src/config.example.yaml ./backend/config.yaml
COPY --from=source /src/extensions_config.example.json ./backend/extensions_config.json

# Built frontend (full directory including node_modules for pnpm start)
COPY --from=frontend-builder /app/frontend ./frontend

ENV DEER_FLOW_HOME=/app/backend/.deer-flow
ENV DEER_FLOW_CONFIG_PATH=/app/backend/config.yaml
ENV DEER_FLOW_EXTENSIONS_CONFIG_PATH=/app/backend/extensions_config.json
ENV NODE_ENV=production
ENV PYTHONPATH=/app/backend

RUN mkdir -p /app/backend/.deer-flow

# Robust startup script:
# - No 'set -e' so one service failure doesn't kill the other
# - Trap SIGTERM/SIGINT to cleanly stop both processes
# - Keeps container alive as long as at least one process runs
RUN cat > /app/start.sh << 'EOF'
#!/bin/sh

cleanup() {
    echo "Shutting down DeerFlow..."
    kill "$BACKEND_PID" "$FRONTEND_PID" 2>/dev/null
    wait
    exit 0
}
trap cleanup TERM INT

echo "Starting DeerFlow backend on :8001..."
cd /app && backend/.venv/bin/uvicorn backend.app.gateway.app:app \
    --host 0.0.0.0 --port 8001 --workers 2 &
BACKEND_PID=$!

echo "Starting DeerFlow frontend on :3000..."
cd /app/frontend && pnpm start &
FRONTEND_PID=$!

echo "DeerFlow running. Backend PID=$BACKEND_PID Frontend PID=$FRONTEND_PID"
wait "$BACKEND_PID" "$FRONTEND_PID"
EOF
chmod +x /app/start.sh

EXPOSE 3000 8001

CMD ["/app/start.sh"]
