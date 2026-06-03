# syntax=docker/dockerfile:1
FROM oven/bun:1 AS base
WORKDIR /app

FROM base AS deps
WORKDIR /app
# Clone target repository and get lockfile
RUN apt-get update && apt-get install -y git && \
    git clone https://github.com/openchamber/openchamber.git .

# Move files to current working directory root to emulate building from source
# but with corrected desktop -> electron path
RUN sed -i 's|COPY packages/desktop/package.json ./packages/desktop/|COPY packages/electron/package.json ./packages/electron/|g' Dockerfile

# Re-run bun install against the cloned repo
RUN bun install --frozen-lockfile --ignore-scripts

FROM deps AS builder
WORKDIR /app
RUN bun run build:web

FROM oven/bun:1 AS runtime
WORKDIR /home/openchamber

RUN apt-get update && apt-get install -y --no-install-recommends \
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
# so mounted volumes with 1000:1000 ownership work correctly.
RUN userdel bun \
  && groupadd -g 1000 openchamber \
  && useradd -u 1000 -g 1000 -m -s /bin/bash openchamber \
  && chown -R openchamber:openchamber /home/openchamber

# Switch to openchamber user
USER openchamber

ENV NPM_CONFIG_PREFIX=/home/openchamber/.npm-global
ENV PATH=${NPM_CONFIG_PREFIX}/bin:${PATH}

RUN npm config set prefix /home/openchamber/.npm-global && mkdir -p /home/openchamber/.npm-global && \
  mkdir -p /home/openchamber/.local /home/openchamber/.config /home/openchamber/.ssh && \
  npm install -g opencode-ai

# cloudflared 2026.3.0 - update digest explicitly when upgrading
COPY --from=cloudflare/cloudflared@sha256:6b599ca3e974349ead3286d178da61d291961182ec3fe9c505e1dd02c8ac31b0 /usr/local/bin/cloudflared /usr/local/bin/cloudflared

ENV NODE_ENV=production

COPY --from=deps /app/scripts/docker-entrypoint.sh /home/openchamber/openchamber-entrypoint.sh

COPY --from=deps /app/node_modules ./node_modules
COPY --from=deps /app/packages/web/node_modules ./packages/web/node_modules
COPY --from=builder /app/package.json ./package.json
COPY --from=builder /app/packages/web/package.json ./packages/web/package.json
COPY --from=builder /app/packages/web/bin ./packages/web/bin
COPY --from=builder /app/packages/web/server ./packages/web/server
COPY --from=builder /app/packages/web/dist ./packages/web/dist

EXPOSE 3000

ENTRYPOINT ["sh", "/home/openchamber/openchamber-entrypoint.sh"]
