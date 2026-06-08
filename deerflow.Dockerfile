# syntax=docker/dockerfile:1
# =============================================================================
# DeerFlow — built from source (works on ARM64 + AMD64)
# Mirrors the official bytedance/deer-flow build pattern exactly.
# Source: https://github.com/bytedance/deer-flow
# =============================================================================

# ── Stage 0: uv binary ─────────────────────────────────────────────────
FROM ghcr.io/astral-sh/uv:0.7.20 AS uv-source

# ── Stage 1: Clone latest DeerFlow source ───────────────────────────────────
FROM alpine/git:latest AS source
WORKDIR /src
ARG CACHE_BUST_DEERFLOW=1
RUN git clone --depth 1 https://github.com/bytedance/deer-flow.git .

# ── Stage 2: Python backend builder ─────────────────────────────────────────
# Copies entire repo (backend/ dir is inside) so uv sync finds pyproject.toml
# at /app/backend/pyproject.toml — exactly as the official Dockerfile does.
FROM python:3.12-slim-bookworm AS backend-builder

ARG NODE_MAJOR=22

COPY --from=uv-source /uv /uvx /usr/local/bin/

# Install build tools + Node.js (required for native Python extensions)
RUN apt-get update && apt-get install -y \
    curl \
    build-essential \
    gnupg \
    ca-certificates \
    && mkdir -p /etc/apt/keyrings \
    && curl -fsSL https://deb.nodesource.com/gpgkey/nodesource-repo.gpg.key \
       | gpg --dearmor -o /etc/apt/keyrings/nodesource.gpg \
    && echo "deb [signed-by=/etc/apt/keyrings/nodesource.gpg] https://deb.nodesource.com/node_${NODE_MAJOR}.x nodistro main" \
       > /etc/apt/sources.list.d/nodesource.list \
    && apt-get update \
    && apt-get install -y nodejs \
    && rm -rf /var/lib/apt/lists/*

WORKDIR /app

# Copy the entire cloned repo so backend/pyproject.toml + backend/uv.lock are present
COPY --from=source /src/backend ./backend

# Install Python deps (uv reads backend/pyproject.toml)
RUN --mount=type=cache,target=/root/.cache/uv \
    cd backend && uv sync

# ── Stage 3: Frontend builder (Next.js) ─────────────────────────────────────
FROM node:22-alpine AS frontend-builder

RUN corepack enable && corepack install -g pnpm@10.26.2

WORKDIR /app

# Copy entire repo so frontend/ is at /app/frontend (matches official pattern)
COPY --from=source /src/frontend ./frontend

RUN cd /app/frontend && pnpm install --frozen-lockfile

# SKIP_ENV_VALIDATION=1 so Next.js doesn't fail because BETTER_AUTH_SECRET
# is not present at build time (it is injected at runtime).
RUN cd /app/frontend && SKIP_ENV_VALIDATION=1 pnpm build

# ── Stage 4: Lean runtime image ───────────────────────────────────────────────
FROM python:3.12-slim-bookworm AS runtime

ENV LANG=C.UTF-8
ENV LC_ALL=C.UTF-8
ENV PYTHONIOENCODING=utf-8

# Copy uv
COPY --from=uv-source /uv /uvx /usr/local/bin/

# Copy Node.js from frontend builder
COPY --from=frontend-builder /usr/local/bin/node /usr/local/bin/node
COPY --from=frontend-builder /usr/local/lib/node_modules /usr/local/lib/node_modules
RUN ln -sf /usr/local/lib/node_modules/npm/bin/npm-cli.js /usr/local/bin/npm \
 && ln -sf /usr/local/lib/node_modules/npm/bin/npx-cli.js /usr/local/bin/npx

WORKDIR /app

# Backend (includes pre-built .venv inside backend/)
COPY --from=backend-builder /app/backend ./backend

# Skills and default configs
COPY --from=source /src/skills ./skills
COPY --from=source /src/config.example.yaml ./backend/config.yaml
COPY --from=source /src/extensions_config.example.json ./backend/extensions_config.json

# Built frontend
COPY --from=frontend-builder /app/frontend ./frontend

# Runtime env vars
ENV DEER_FLOW_HOME=/app/backend/.deer-flow
ENV DEER_FLOW_CONFIG_PATH=/app/backend/config.yaml
ENV DEER_FLOW_EXTENSIONS_CONFIG_PATH=/app/backend/extensions_config.json
ENV NODE_ENV=production
ENV PYTHONPATH=/app

# Create persistent data directory
RUN mkdir -p /app/backend/.deer-flow

# Startup: run backend (port 8001) and frontend (port 3000) concurrently
RUN printf '#!/bin/sh\nset -e\n\n# Backend API\ncd /app && backend/.venv/bin/uvicorn backend.app.gateway.app:app --host 0.0.0.0 --port 8001 &\n\n# Frontend\ncd /app/frontend && pnpm start &\n\nwait\n' > /app/start.sh && chmod +x /app/start.sh

EXPOSE 3000 8001

CMD ["/app/start.sh"]
