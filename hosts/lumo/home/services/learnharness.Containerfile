# LearnHarness browser-mode server (Next.js standalone output).
# Build context: the pinned upstream source tree from learnharness.nix.
# The base image is passed in digest-pinned; upstream CI builds on Node 26.
ARG NODE_IMAGE

FROM ${NODE_IMAGE} AS build
WORKDIR /src
COPY . .
# Electron is a devDependency for the desktop shell only; never download it.
ENV ELECTRON_SKIP_BINARY_DOWNLOAD=1 \
    NEXT_TELEMETRY_DISABLED=1 \
    npm_config_audit=false \
    npm_config_fund=false
# build-server.mjs copies public/ and .next/static into the standalone tree
# and refuses to continue if data/ or credential files were traced into it.
RUN npm ci \
 && npm run build \
 && node scripts/build-server.mjs
# Lets lumo prune superseded build stages without touching other images.
LABEL dev.justaslime.app=learnharness

FROM ${NODE_IMAGE}
ENV NODE_ENV=production \
    NEXT_TELEMETRY_DISABLED=1 \
    HOME=/data/home \
    LH_DATA_DIR=/data/data \
    LH_AUTH_FILE=/data/auth/auth.json
# Root-owned code; only /data (bind mount) and the cache tmpfs are writable.
COPY --from=build /src/.next/standalone /app
WORKDIR /app
USER node
LABEL dev.justaslime.app=learnharness
CMD ["node", "server.js"]
