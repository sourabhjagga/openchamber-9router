# syntax=docker/dockerfile:1
# =============================================================================
# DeerFlow — built from source (supports ARM64 + AMD64)
# Source: https://github.com/bytedance/deer-flow
# =============================================================================

# ── Stage 1: Clone latest source ─────────────────────────────────────────────
FROM alpine/git:latest AS source
WORKDIR /src
ARG CACHE_BUST_DEERFLOW=1
RUN git clone --depth 1 https://github.com/bytedance/deer-flow.git .

# ── Stage 2: Build Frontend (Next.js) ────────────────────────────────────────
FROM node:20-slim AS frontend-builder
WORKDIR /app/frontend

RUN npm install -g pnpm

COPY --from=source /src/frontend/package.json ./package.json
COPY --from=source /src/frontend/pnpm-lock.yaml ./pnpm-lock.yaml
RUN pnpm install --frozen-lockfile

COPY --from=source /src/frontend ./

# Build with dummy BETTER_AUTH_SECRET so Next.js doesn't fail at build time
RUN BETTER_AUTH_SECRET=buildsecret pnpm run build

# ── Stage 3: Python backend (uv) ─────────────────────────────────────────────
FROM python:3.12-slim AS backend-builder
WORKDIR /app

RUN pip install uv

COPY --from=source /src/backend ./backend
COPY --from=source /src/pyproject.toml ./pyproject.toml
COPY --from=source /src/uv.lock ./uv.lock

# Install Python dependencies into a virtual env
RUN uv sync --frozen --no-dev

# ── Stage 4: Runtime image ───────────────────────────────────────────────────
FROM python:3.12-slim AS runtime
WORKDIR /app

# Runtime system deps
RUN apt-get update && apt-get install -y --no-install-recommends \
    curl \
    nodejs \
    npm \
    && rm -rf /var/lib/apt/lists/*

RUN npm install -g pnpm

# Copy Python virtualenv and backend
COPY --from=backend-builder /app/.venv /app/.venv
COPY --from=backend-builder /app/backend /app/backend
COPY --from=source /src/pyproject.toml /app/pyproject.toml
COPY --from=source /src/skills /app/skills
COPY --from=source /src/config.example.yaml /app/backend/config.yaml
COPY --from=source /src/extensions_config.example.json /app/backend/extensions_config.json

# Copy built frontend
COPY --from=frontend-builder /app/frontend/.next/standalone /app/frontend-server
COPY --from=frontend-builder /app/frontend/.next/static /app/frontend-server/.next/static
COPY --from=frontend-builder /app/frontend/public /app/frontend-server/public

# Activate virtualenv
ENV PATH="/app/.venv/bin:$PATH"
ENV PYTHONPATH=/app
ENV DEER_FLOW_HOME=/app/backend/.deer-flow
ENV DEER_FLOW_CONFIG_PATH=/app/backend/config.yaml
ENV DEER_FLOW_EXTENSIONS_CONFIG_PATH=/app/backend/extensions_config.json
ENV NODE_ENV=production

# Create persistent data dir
RUN mkdir -p /app/backend/.deer-flow

# Startup script: run both backend API and frontend
RUN printf '#!/bin/sh\nset -e\n# Start backend\ncd /app && uvicorn backend.app.gateway.app:app --host 0.0.0.0 --port 8001 &\n# Start frontend\ncd /app/frontend-server && node server.js &\nwait\n' > /app/start.sh && chmod +x /app/start.sh

EXPOSE 3000 8001

CMD ["/app/start.sh"]
