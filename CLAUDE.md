# CLAUDE.md

Project context for Claude Code. Read this before making changes.

## What this is

A self-hosted, S3-compatible object storage stack — a drop-in alternative to
Cloudflare R2 — that you run with Docker Compose. Two services:

- **MinIO server** — the storage engine / S3 API (data plane). Port **9000**.
- **OpenMaxIO console** — the full admin dashboard (buckets, users, policies,
  access keys, upload/browse). Port **9090**. This is a community fork that
  restores the admin UI MinIO stripped out of its open-source edition in 2025.

## Files

| File | Purpose |
|------|---------|
| `docker-compose.yml` | The stack (minio + console-init + console). |
| `Dockerfile` | Builds the OpenMaxIO console from source. |
| `.env.example` | Template for credentials + console secrets. Copy to `.env`. |
| `.env` | Real secrets — **gitignored, never commit**. |
| `README.md` | Human setup guide, usage, hardening, caveats. |

## Run / verify

```bash
cp .env.example .env        # then edit: set strong MINIO_ROOT_PASSWORD + CONSOLE_PBKDF_* secrets
docker compose up -d --build   # first build compiles the console from source (~minutes)
docker compose logs -f console # watch console startup
docker compose ps              # health
docker compose down            # stop (add -v to also wipe the data volume)
```

- Console UI: http://localhost:9090 — log in with `CONSOLE_ACCESS_KEY` / `CONSOLE_SECRET_KEY`
  from `.env` (the dedicated admin user, auto-provisioned by `console-init`; not root).
- S3 endpoint for apps: http://localhost:9000, region `us-east-1`, path-style addressing on.

## Key decisions & constraints (don't undo these without reason)

- **OpenMaxIO has no official Docker image**, so we build it from source in the
  `Dockerfile` (pinned to `OPENMAXIO_REF=v1.7.6`). There are unofficial community
  images (referenced, commented out, in `docker-compose.yml`) — treat them as
  untrusted; they'd hold admin-level access to storage. Don't switch to one by
  default. If you ever do, pin by digest.
- **The source build needs two patches** (both already in the `Dockerfile`):
  (1) **Corepack** is enabled so the web-app's pinned **Yarn 4.4.0** is used —
  installing classic `yarn@1` makes `yarn install` refuse to run. (2) The web-app
  pins its `mds` design-system dependency at `minio/mds`, which MinIO **deleted**
  (GitHub 404 as of 2025; even OpenMaxIO v2.x still points there). We `sed`-repoint
  the host to the live **`OpenMaxIO/mds`** fork in `package.json` + `yarn.lock`; the
  fork has the same tag and pinned commit, so the lockfile stays valid and
  `--immutable` passes. Without these the build fails. Harmless warnings during the
  build: a `typescript` builtin compat patch (`optional`, skipped) and a `canvas`
  native-dep build failure (unused by the UI). The console has a fixed
  `container_name`, so a leftover `openmaxio-console` container can block `up` with
  a name conflict — clear it with `docker rm -f openmaxio-console`.
- **MinIO's public images are frozen** (updates stopped ~Oct 2025; the Community
  Edition went source-only). We pin `quay.io/minio/minio:RELEASE.2025-07-23T15-54-02Z`.
  It works but gets no security patches. For ongoing patches, the migration path is
  Chainguard's maintained image (`cgr.dev/chainguard/minio`) or building MinIO from source.
- **`MINIO_BROWSER: "off"`** is intentional — OpenMaxIO replaces MinIO's built-in
  basic browser. The S3 API *and* the admin API (which the console depends on) stay
  available on 9000 regardless.
- The console requires `CONSOLE_MINIO_SERVER` plus `CONSOLE_PBKDF_PASSPHRASE` and
  `CONSOLE_PBKDF_SALT` (session-JWT encryption). All secrets live in `.env`.
- **`console-init`** (one-shot, `quay.io/minio/mc` pinned by digest) provisions a
  dedicated non-root admin user from `CONSOLE_ACCESS_KEY` / `CONSOLE_SECRET_KEY`
  after MinIO is healthy, then exits. It's idempotent and re-applies the secret
  each `up`, so `.env` is the source of truth. It attaches MinIO's **built-in**
  `consoleAdmin` policy (admin:* + kms:* + s3:*) — don't add a redundant custom
  policy of the same name; the builtin shadows it. `console`
  `depends_on console-init: service_completed_successfully`, so a bad
  `CONSOLE_SECRET_KEY` fails fast and blocks the console (intentional). Root creds
  are only for bootstrap, not day-to-day login. Every secret in `.env` must be a
  distinct random — never reuse one value across fields.
- **The provisioning script is inlined** in the `console-init` `command` (not a
  mounted file), so it travels with the compose file and deploys anywhere. Don't
  switch it back to a bind-mounted `./bootstrap.sh`: on a PaaS like Coolify the
  source path often isn't present, and Docker silently creates `/bootstrap.sh` as
  a **directory**, so the container dies with `/bootstrap.sh: Is a directory`. In
  the inlined script, shell variables use `$$` to escape Compose interpolation.
- Runtime image for the console is `distroless/static` (`:nonroot`). If the console
  fails at startup needing a writable home, drop the `:nonroot` tag.

## Open work / likely next steps

1. **Reverse proxy + HTTPS** (Caddy or Traefik) in front of 9000 and 9090 before
   this is exposed beyond localhost. This is the top priority before any remote use.
2. **Backups** for the `minio-data` volume (that's where all objects live).
3. Consider migrating the MinIO image to a maintained build (see constraints above).

Done: dedicated non-root console user is now auto-provisioned by the `console-init`
service (inlined script; was a manual `mc` step).

## Conventions

- Never commit `.env` or any real credentials.
- Pin image tags (prefer digests for anything third-party).
- Keep `README.md` (human-facing) and this file (agent-facing) in sync when the
  architecture or run steps change.