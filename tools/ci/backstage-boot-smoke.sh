#!/usr/bin/env bash
# Copyright (c) 2026 VitruvianSoftware
#
# Permission is hereby granted, free of charge, to any person obtaining a copy
# of this software and associated documentation files (the "Software"), to deal
# in the Software without restriction, including without limitation the rights
# to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
# copies of the Software, and to permit persons to whom the Software is
# furnished to do so, subject to the following conditions:
#
# The above copyright notice and this permission notice shall be included in
# all copies or substantial portions of the Software.
#
# THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
# IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
# FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
# AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
# LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
# OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE

# Boots the built backstage container against a throwaway Postgres and asserts
# that every backend plugin initializes and the service reports READY.
#
# Why this exists: #1709 registered a GitHub auth provider whose sign-in
# resolver was named in app-config but no longer existed. The auth plugin threw
# during initialization -- the process stayed up, liveness kept returning 200,
# readiness returned 503 forever, ArgoCD went Degraded, and the previous
# ReplicaSet kept serving. `kubectl get pods` looked unremarkable. That change
# shipped with 11 green unit tests, all exercising a pure predicate; none
# started the backend, so none could have caught it.
#
# Two deliberate choices:
#   * test the IMAGE, not the sources -- it exercises the artifact that deploys
#     (bundle unpacking, prod-only dependency layout) rather than a code path
#     that only exists on a developer laptop;
#   * use Postgres, not sqlite -- better-sqlite3's native bindings are not built
#     in the production image, and prod runs Postgres regardless.
#
# Usage: backstage-boot-smoke.sh <image-ref>
set -euo pipefail

IMAGE="${1:?usage: backstage-boot-smoke.sh <image-ref>}"
SFX="$$"
NET="backstage-smoke-net-$SFX"
PG="backstage-smoke-pg-$SFX"
APP="backstage-smoke-app-$SFX"
CFG="$(mktemp -t bs-smoke-XXXXXX.yaml)"

cleanup() {
  docker rm -f "$APP" "$PG" >/dev/null 2>&1 || true
  docker network rm "$NET" >/dev/null 2>&1 || true
  rm -f "$CFG"
}
trap cleanup EXIT

# Prints the backend's own error lines, trimmed. Raw output is JSON with a full
# stack per plugin -- one wedged service produces ~40KB, which buries the signal.
show_errors() {
  docker logs "$APP" 2>&1 \
    | grep '"level":"error"' \
    | grep -oE '"message":"[^"]{0,200}' \
    | sed 's/^"message":"/  /' \
    | head -4 >&2
}

docker network create "$NET" >/dev/null

echo "boot-smoke: starting postgres ..."
docker run -d --name "$PG" --network "$NET" \
  -e POSTGRES_PASSWORD=smoke -e POSTGRES_USER=postgres \
  postgres:16-alpine >/dev/null
# Success is decided INSIDE the loop. The previous form broke on the first
# successful probe and then re-verified with a separate one-shot check, so a
# transient ready could pass the loop and fail the check -- which is exactly
# what CI hit (the step failed 1.3s in, far too fast to have exhausted its
# attempts). -h 127.0.0.1 for the same reason: initdb runs a temporary server
# on the unix socket before restarting for real, and it never listens on TCP.
PG_READY=""
for _ in $(seq 1 60); do
  if docker exec "$PG" pg_isready -h 127.0.0.1 -U postgres >/dev/null 2>&1; then
    PG_READY=yes; break
  fi
  sleep 1
done
[ -n "$PG_READY" ] || { echo "boot-smoke: ✗ postgres never became ready" >&2; exit 1; }

# Generated, never committed: backend.auth.keys[].secret must be valid base64,
# and a literal base64 blob in the repo is indistinguishable from a real leaked
# key -- to gitleaks (which flagged exactly this) and to a human reading it.
SMOKE_KEY="$(printf 'boot-smoke-ephemeral-key' | base64)"

# Minimal config: the point is not to exercise real integrations, it is to prove
# every plugin this backend registers can initialize. auth/permission/kubernetes
# mirror production so the org sign-in resolver, the Vitruvian permission policy
# and the k8s cluster locator are all actually constructed.
cat > "$CFG" <<YAML
backend:
  baseUrl: http://localhost:7007
  listen: { host: 0.0.0.0, port: 7007 }
  database:
    client: pg
    connection:
      host: $PG
      port: 5432
      user: postgres
      password: smoke
  auth:
    keys:
      - secret: $SMOKE_KEY
app:
  baseUrl: http://localhost:7007
auth:
  environment: development
  providers:
    github:
      development:
        clientId: smoke-client-id
        clientSecret: smoke-client-secret
permission:
  enabled: true
kubernetes:
  serviceLocatorMethod: { type: multiTenant }
  clusterLocatorMethods:
    - type: config
      clusters:
        - name: smoke
          url: https://kubernetes.default.svc
          authProvider: serviceAccount
          skipTLSVerify: true
          serviceAccountToken: smoke-token
catalog:
  locations: []
techdocs:
  builder: local
  generator: { runIn: local }
  publisher: { type: local }
YAML

echo "boot-smoke: starting $IMAGE ..."
# create+cp+start rather than `docker run -v`: a bind mount depends on the host
# temp dir being in Docker's file-sharing list, which it is not on macOS (Docker
# silently substitutes an empty DIRECTORY and the backend dies with EISDIR).
# 0644 because mktemp creates 0600 root-owned and the image runs as non-root.
chmod 0644 "$CFG"
docker create --name "$APP" --network "$NET" -p 17007:7007 "$IMAGE" \
  node packages/backend/dist/index.cjs.js --config /app/app-config.smoke.yaml >/dev/null
docker cp "$CFG" "$APP:/app/app-config.smoke.yaml" >/dev/null
docker start "$APP" >/dev/null

DEADLINE=$(( SECONDS + 150 ))
STATUS="timeout"
while [ "$SECONDS" -lt "$DEADLINE" ]; do
  if ! docker ps -q --filter "name=$APP" | grep -q .; then STATUS="died"; break; fi
  LOGS="$(docker logs "$APP" 2>&1 || true)"
  # Fail fast on the #1709 signature instead of waiting out the deadline.
  if grep -qE "threw an error during startup|BackendStartupError|startup failed" <<<"$LOGS"; then
    STATUS="startup-error"; break
  fi
  # Success needs BOTH: plugins initialized AND readiness actually serving 200.
  # Liveness alone is not enough -- that is exactly what stayed green while
  # #1709 was wedged.
  if grep -q "Plugin initialization complete" <<<"$LOGS" \
     && [ "$(curl -fsS -o /dev/null -w '%{http_code}' http://localhost:17007/.backstage/health/v1/readiness 2>/dev/null || true)" = "200" ]; then
    STATUS="ok"; break
  fi
  sleep 2
done

case "$STATUS" in
  ok)
    echo "boot-smoke: ✓ all plugins initialized and readiness returned 200" ;;
  startup-error)
    echo "boot-smoke: ✗ a plugin failed to initialize" >&2; show_errors; exit 1 ;;
  died)
    echo "boot-smoke: ✗ container exited before becoming ready" >&2; show_errors; exit 1 ;;
  *)
    echo "boot-smoke: ✗ timed out after 150s without reaching readiness" >&2; show_errors; exit 1 ;;
esac
