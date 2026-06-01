# syntax=docker/dockerfile:1

# =============================================================================
# Build stage — compile the OpenMaxIO console binary (Go) with its embedded
# web app (React/TS). Follows the project's documented build steps.
# =============================================================================
FROM golang:1.24-bookworm AS build

ARG OPENMAXIO_REF=v1.7.6
ENV CGO_ENABLED=0

# Tooling: git + make for the Go build, Node.js 20 for the front-end. The web-app
# pins Yarn 4 via package.json "packageManager", so we enable Corepack (bundled
# with Node 20) and let it supply that exact Yarn — installing classic yarn@1
# makes `yarn install` refuse to run. python3/build-essential cover node-gyp deps.
RUN apt-get update \
 && apt-get install -y --no-install-recommends \
        ca-certificates git make curl python3 build-essential \
 && curl -fsSL https://deb.nodesource.com/setup_20.x | bash - \
 && apt-get install -y --no-install-recommends nodejs \
 && corepack enable \
 && rm -rf /var/lib/apt/lists/*

WORKDIR /src
RUN git clone https://github.com/OpenMaxIO/openmaxio-object-browser . \
 && git checkout "${OPENMAXIO_REF}"

# Build the front-end first — its output gets embedded into the Go binary.
#
# Upstream pins the web-app's `mds` design-system dependency at the now-deleted
# minio/mds repo (GitHub 404s it as of 2025; even OpenMaxIO v2.x still points
# there). The OpenMaxIO/mds fork carries the same tags AND the same pinned commit
# (027fb7f…), so we repoint just the host in package.json + yarn.lock — identical
# content means the lockfile stays valid and `--immutable` still passes.
#
# Corepack resolves the Yarn version pinned in web-app/package.json on first run.
# (--immutable is Yarn 4's equivalent of classic Yarn's --frozen-lockfile.)
RUN cd web-app \
 && sed -i 's#github.com/minio/mds.git#github.com/OpenMaxIO/mds.git#g' package.json yarn.lock \
 && yarn install --immutable \
 && yarn build

# Build the console binary (produces ./console in the repo root).
RUN make console

# =============================================================================
# Runtime stage — tiny static image holding just the binary.
# (If the console errors on startup needing a writable home, swap this line
#  for `gcr.io/distroless/static-debian12` — i.e. drop the :nonroot tag.)
# =============================================================================
FROM gcr.io/distroless/static-debian12:nonroot

COPY --from=build /src/console /console
EXPOSE 9090
ENTRYPOINT ["/console"]
CMD ["server"]