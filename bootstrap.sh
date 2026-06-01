#!/bin/sh
# Provision the dedicated MinIO admin user that the OpenMaxIO console logs in
# with, instead of using the MinIO root account. Runs as a one-shot init
# container (the `console-init` service in docker-compose.yml) after MinIO is
# healthy, then exits.
#
# Idempotent: safe to re-run on every `docker compose up`. The console user's
# secret is re-applied from CONSOLE_SECRET_KEY each run, so .env stays the single
# source of truth — rotate the secret there and bring the stack up again.
set -eu

ENDPOINT="${MINIO_ENDPOINT:-http://minio:9000}"
ALIAS=minio

# consoleAdmin is MinIO's built-in admin policy (admin:* + kms:* + s3:* on all
# resources) — exactly the "full admin for the console" grant we want, so we
# attach it rather than redefining it. For a least-privilege console user,
# create your own policy (`mc admin policy create`) and point POLICY at it.
POLICY=consoleAdmin

# Fail fast if any required secret is missing / empty.
: "${MINIO_ROOT_USER:?MINIO_ROOT_USER is required}"
: "${MINIO_ROOT_PASSWORD:?MINIO_ROOT_PASSWORD is required}"
: "${CONSOLE_ACCESS_KEY:?CONSOLE_ACCESS_KEY is required}"
: "${CONSOLE_SECRET_KEY:?CONSOLE_SECRET_KEY is required}"

# Wait until MinIO accepts the root credentials (depends_on healthy should mean
# it already does; the loop covers DNS / startup races).
echo "console-init: waiting for MinIO at ${ENDPOINT} ..."
until mc alias set "$ALIAS" "$ENDPOINT" "$MINIO_ROOT_USER" "$MINIO_ROOT_PASSWORD" >/dev/null 2>&1; do
  sleep 2
done

# Console user. Re-adding an existing access key updates its secret (declarative).
mc admin user add "$ALIAS" "$CONSOLE_ACCESS_KEY" "$CONSOLE_SECRET_KEY" >/dev/null
echo "console-init: ensured user '${CONSOLE_ACCESS_KEY}'"

# Bind the admin policy to the user. On re-run MinIO reports "already in effect"
# — that's the desired end state, so treat it as success.
mc admin policy attach "$ALIAS" "$POLICY" --user "$CONSOLE_ACCESS_KEY" >/dev/null 2>&1 \
  || echo "console-init: policy '${POLICY}' already attached to '${CONSOLE_ACCESS_KEY}'"

echo "console-init: done — '${CONSOLE_ACCESS_KEY}' has policy '${POLICY}'"
