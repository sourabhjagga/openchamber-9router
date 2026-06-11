# syntax=docker/dockerfile:1
FROM oven/bun:1 AS base
WORKDIR /app

# ── Stage 1: fetch source ────────────────────────────────────────────────────
# This stage clones the repo. It is intentionally kept separate so that
# dependency install (Stage 2) can be cached independently.
FROM base AS source
WORKDIR /app

# CACHE_BUST_STATIC: only increment to deliberately wipe openchamber data.
ARG CACHE_BUST_STATIC=1

RUN apt-get update && apt-get install -y git && \
    git clone https://github.com/openchamber/openchamber.git . && \
    sed -i "s|req.path.startsWith('/api/session-folders') |||req.path.startsWith('/api/session-folders') \|\|\\n      req.path.startsWith('/api/session') \|\||" packages/web/server/lib/opencode/core-routes.js


# ── Stage 2: install dependencies ───────────────────────────────────────────
# Docker caches this layer. It only re-runs if bun.lockb or package.json
# files change in the cloned repo - not on every redeploy.
FROM source AS deps
WORKDIR /app
RUN bun install --frozen-lockfile --ignore-scripts

# ── Stage 3: build web assets ────────────────────────────────────────────────
# Only re-runs if source files actually changed.
FROM deps AS builder
WORKDIR /app
RUN bun run build:web

# ── Stage 4: lean runtime image ─────────────────────────────────────────────
FROM oven/bun:1 AS runtime
WORKDIR /home/openchamber

RUN export DEBIAN_FRONTEND=noninteractive && \
    apt-get update && apt-get install -y --no-install-recommends \
  bash \
  ca-certificates \
  git \
  less \
  nodejs \
  npm \
  openssh-client \
  python3 \
  && rm -rf /var/lib/apt/lists/*

# Replace the base image's 'bun' user (UID 1000) with 'openchamber'
RUN userdel bun \
  && groupadd -g 1000 openchamber \
  && useradd -u 1000 -g 1000 -m -s /bin/bash openchamber \
  && chown -R openchamber:openchamber /home/openchamber

ENV NPM_CONFIG_PREFIX=/home/openchamber/.npm-global
ENV PATH=${NPM_CONFIG_PREFIX}/bin:${PATH}

RUN mkdir -p /home/openchamber/.npm-global \
             /home/openchamber/.local/share/opencode \
             /home/openchamber/.local/state/opencode \
             /home/openchamber/.config/opencode \
             /home/openchamber/.config/openchamber \
             /home/openchamber/.ssh \
             /home/openchamber/workspaces \
  && chown -R openchamber:openchamber /home/openchamber

USER openchamber

RUN npm config set prefix /home/openchamber/.npm-global && \
  npm install -g opencode-ai

# cloudflared - update digest when upgrading
COPY --from=cloudflare/cloudflared@sha256:6b599ca3e974349ead3286d178da61d291961182ec3fe9c505e1dd02c8ac31b0 /usr/local/bin/cloudflared /usr/local/bin/cloudflared

ENV NODE_ENV=production

COPY --from=source /app/scripts/docker-entrypoint.sh /home/openchamber/openchamber-entrypoint.sh

COPY --from=deps /app/node_modules ./node_modules
COPY --from=deps /app/packages/web/node_modules ./packages/web/node_modules
COPY --from=builder /app/package.json ./package.json
COPY --from=builder /app/packages/web/package.json ./packages/web/package.json
COPY --from=builder /app/packages/web/bin ./packages/web/bin
COPY --from=builder /app/packages/web/server ./packages/web/server
COPY --from=builder /app/packages/web/dist ./packages/web/dist

EXPOSE 3000

ENTRYPOINT ["sh", "/home/openchamber/openchamber-entrypoint.sh"]
