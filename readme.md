# Self-hosted S3 (R2 alternative): MinIO + OpenMaxIO console

MinIO server gives you S3-compatible object storage. OpenMaxIO restores the full
admin console MinIO removed from its open-source edition in 2025 (buckets, users,
policies, access keys, upload/browse).

Files:
- `docker-compose.yml` — the stack (MinIO + console)
- `Dockerfile` — builds the OpenMaxIO console from source
- `.env.example` — credentials + secrets (copy to `.env`)

---

## Setup

1. **Prereqs:** Docker and Docker Compose v2 installed.

2. **Save the files** into one directory (`docker-compose.yml`, `Dockerfile`, `.env.example`).

3. **Create your env file and set strong values:**
   ```bash
   cp .env.example .env
   # edit .env — set, as distinct random values:
   #   MINIO_ROOT_PASSWORD, CONSOLE_PBKDF_PASSPHRASE, CONSOLE_PBKDF_SALT, CONSOLE_SECRET_KEY
   # quick way to generate secrets (never reuse one value across fields):
   openssl rand -hex 32
   ```

4. **Bring it up** (first run builds the console from source — a few minutes):
   ```bash
   docker compose up -d --build
   ```

5. **Open the console:** http://localhost:9090
   Log in with `CONSOLE_ACCESS_KEY` / `CONSOLE_SECRET_KEY` from your `.env`. This
   dedicated admin user is created automatically on startup by the `console-init`
   service (you don't log in as root).

6. **Create a bucket** in the console, then go to **Access Keys → Create access key**
   to mint an access key + secret for your applications.

---

## Using it as your R2 replacement

Point any S3 SDK or tool at the API endpoint with the access key you created:

- **Endpoint:** `http://localhost:9000` (or your server IP / domain)
- **Region:** `us-east-1` (any value works; this is the conventional default)
- **Path-style addressing:** enabled (`forcePathStyle: true` in most SDKs)

Quick check with the AWS CLI:
```bash
export AWS_ACCESS_KEY_ID=your-access-key
export AWS_SECRET_ACCESS_KEY=your-secret-key
aws --endpoint-url http://localhost:9000 s3 ls
aws --endpoint-url http://localhost:9000 s3 cp ./photo.jpg s3://your-bucket/
```

Switching an app from R2 to this is usually just changing the endpoint URL and keys.

---

## Dedicated console user (automatic)

You log into the console as a dedicated **non-root** admin user, not as root. The
`console-init` service handles this for you: on every `docker compose up` it waits
for MinIO to be healthy, then creates/updates the user from `.env` and attaches
MinIO's built-in `consoleAdmin` policy (full admin), then exits. Logic lives in
`bootstrap.sh`.

Configure it in `.env`:

```bash
CONSOLE_ACCESS_KEY=console
CONSOLE_SECRET_KEY=your-long-random-secret   # openssl rand -hex 24
```

- **Rotate the secret:** change `CONSOLE_SECRET_KEY` in `.env`, then `docker compose up -d`
  — `console-init` re-applies it (the file is the source of truth).
- **Fail-fast:** `console` waits for `console-init` to succeed, so an empty/invalid
  secret blocks the console instead of silently falling back to root. To log in as
  root instead, remove the `console-init` service and its `depends_on` entry.
- **Least privilege:** for a restricted console user, create your own policy with
  `mc admin policy create` and point `POLICY` in `bootstrap.sh` at it.

> Root credentials (`MINIO_ROOT_USER` / `MINIO_ROOT_PASSWORD`) are now only used to
> bootstrap that user — keep them strong and private. Note MinIO reads root creds
> from the environment at every boot, so changing them takes effect on the next
> `docker compose up` (no volume wipe needed); the data volume holds your objects,
> buckets, and non-root users.

---

## Important notes

- **MinIO images are frozen.** MinIO stopped updating its public Docker/Quay images
  around Oct 2025 and made the Community Edition source-only. The pinned release here
  works, but won't receive security updates. For ongoing patches, consider Chainguard's
  maintained image (`cgr.dev/chainguard/minio:latest`) or rebuild from source yourself.

- **No official OpenMaxIO image exists.** Building from source (the default here) avoids
  handing admin-level access to an unvetted third-party image. The commented-out prebuilt
  image in the compose is a convenience only — if you use it, pin it by digest and review it.

- **Don't expose ports 9000/9090 to the internet as-is.** Put them behind a reverse proxy
  with HTTPS (Caddy/Traefik/nginx) and restrict access before going beyond localhost.

- **Back up the `minio-data` volume** — that's where all your objects live.