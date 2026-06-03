FROM oven/bun:1 AS base
WORKDIR /app

# Clone the repository
RUN apt-get update && apt-get install -y git && \
    git clone https://github.com/openchamber/openchamber.git . && \
    sed -i 's|COPY packages/desktop/package.json ./packages/desktop/|COPY packages/electron/package.json ./packages/electron/|g' Dockerfile

# Start the actual build stages based on the fixed Dockerfile
FROM base AS deps
WORKDIR /app
COPY --from=base /app/package.json /app/bun.lock ./
COPY --from=base /app/packages/ui/package.json ./packages/ui/
COPY --from=base /app/packages/web/package.json ./packages/web/
COPY --from=base /app/packages/electron/package.json ./packages/electron/
COPY --from=base /app/packages/vscode/package.json ./packages/vscode/
RUN bun install --frozen-lockfile --ignore-scripts

FROM deps AS builder
WORKDIR /app
COPY --from=base /app .
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

RUN userdel bun \
  && groupadd -g 1000 openchamber \
  && useradd -u 1000 -g 1000 -m -s /bin/bash openchamber \
  && chown -R openchamber:openchamber /home/openchamber

USER openchamber
ENV NPM_CONFIG_PREFIX=/home/openchamber/.npm-global
ENV PATH=${NPM_CONFIG_PREFIX}/bin:${PATH}

RUN npm config set prefix /home/openchamber/.npm-global && mkdir -p /home/openchamber/.npm-global && \
  mkdir -p /home/openchamber/.local /home/openchamber/.config /home/openchamber/.ssh && \
  npm install -g opencode-ai

COPY --from=cloudflare/cloudflared@sha256:6b599ca3e974349ead3286d178da61d291961182ec3fe9c505e1dd02c8ac31b0 /usr/local/bin/cloudflared /usr/local/bin/cloudflared
ENV NODE_ENV=production

COPY --from=base /app/scripts/docker-entrypoint.sh /home/openchamber/openchamber-entrypoint.sh
COPY --from=deps /app/node_modules ./node_modules
COPY --from=deps /app/packages/web/node_modules ./packages/web/node_modules
COPY --from=builder /app/package.json ./package.json
COPY --from=builder /app/packages/web/package.json ./packages/web/package.json
COPY --from=builder /app/packages/web/bin ./packages/web/bin
COPY --from=builder /app/packages/web/server ./packages/web/server
COPY --from=builder /app/packages/web/dist ./packages/web/dist

EXPOSE 3000
ENTRYPOINT ["sh", "/home/openchamber/openchamber-entrypoint.sh"]
