#!/usr/bin/env bash
set -euo pipefail

repo_root=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
cd "$repo_root"

project="searxng-acceptance-${RANDOM}-$$"
network="${project}_search"
port=$(python3 - <<'PY'
import socket
with socket.socket() as sock:
    sock.bind(("127.0.0.1", 0))
    print(sock.getsockname()[1])
PY
)
marker="hermes-searxng-canary-${RANDOM}-$$"

export BIND_ADDRESS=127.0.0.1
export PUBLISHED_PORT="$port"
export SEARCH_SUBNET=10.253.250.0/24
export ALLOWED_CIDR="$SEARCH_SUBNET"
export SEARXNG_SECRET
SEARXNG_SECRET=$(python3 -c 'import secrets; print(secrets.token_urlsafe(48))')

cleanup() {
  docker compose -p "$project" down --volumes --remove-orphans >/dev/null 2>&1 || true
}
trap cleanup EXIT INT TERM

docker compose -p "$project" config --quiet
docker compose -p "$project" up -d

searxng_id=$(docker compose -p "$project" ps -q searxng)
ingress_id=$(docker compose -p "$project" ps -q ingress)
[ -n "$searxng_id" ]
[ -n "$ingress_id" ]

ready=false
for _ in $(seq 1 60); do
  searxng_health=$(docker inspect --format '{{if .State.Health}}{{.State.Health.Status}}{{else}}none{{end}}' "$searxng_id")
  ingress_health=$(docker inspect --format '{{if .State.Health}}{{.State.Health.Status}}{{else}}none{{end}}' "$ingress_id")
  if [ "$searxng_health" = healthy ] && [ "$ingress_health" = healthy ]; then
    ready=true
    break
  fi
  if [ "$(docker inspect --format '{{.State.Status}}' "$searxng_id")" = exited ] || \
     [ "$(docker inspect --format '{{.State.Status}}' "$ingress_id")" = exited ]; then
    docker compose -p "$project" logs --no-color
    printf 'A service exited before readiness\n' >&2
    exit 1
  fi
  sleep 2
done
if [ "$ready" != true ]; then
  printf 'Readiness timed out: searxng=%s ingress=%s\n' \
    "$(docker inspect --format '{{if .State.Health}}{{.State.Health.Status}}{{else}}none{{end}}' "$searxng_id")" \
    "$(docker inspect --format '{{if .State.Health}}{{.State.Health.Status}}{{else}}none{{end}}' "$ingress_id")" >&2
  docker inspect --format '{{json .State.Health}}' "$searxng_id" >&2 || true
  docker inspect --format '{{json .State.Health}}' "$ingress_id" >&2 || true
  docker compose -p "$project" logs --no-color >&2 || true
  exit 1
fi

# The SearXNG service itself must have no host port publication.
python3 - "$searxng_id" <<'PY'
import json
import subprocess
import sys
raw = subprocess.check_output(
    ["docker", "inspect", "--format", "{{json .HostConfig.PortBindings}}", sys.argv[1]],
    text=True,
).strip()
value = json.loads(raw) if raw not in ("", "null") else None
if value not in (None, {}):
    raise SystemExit(f"SearXNG unexpectedly publishes host ports: {value}")
PY

# An allowlisted peer on the stack network must return valid JSON and real results.
search_json=$(docker run --rm \
  --network "$network" \
  --entrypoint sh \
  docker.io/library/caddy@sha256:4c6e91c6ed0e2fa03efd5b44747b625fec79bc9cd06ac5235a779726618e530d \
  -c "wget -qO- 'http://ingress:8080/search?q=OpenAI%20Hermes%20${marker}&format=json'")
python3 - "$search_json" <<'PY'
import json
import sys
payload = json.loads(sys.argv[1])
results = payload.get("results")
if not isinstance(results, list) or not results:
    raise SystemExit("JSON search returned no results")
print(f"JSON_SEARCH_RESULTS={len(results)}")
PY

# A host-origin request is outside the allowlisted stack subnet and must get 403.
python3 - "$port" <<'PY'
import sys
import urllib.error
import urllib.request
try:
    urllib.request.urlopen(f"http://127.0.0.1:{sys.argv[1]}/healthz", timeout=10)
except urllib.error.HTTPError as exc:
    if exc.code != 403:
        raise SystemExit(f"non-allowlisted request returned HTTP {exc.code}, expected 403")
    print("NON_ALLOWLISTED_HTTP=403")
else:
    raise SystemExit("non-allowlisted request unexpectedly succeeded")
PY

# The synthetic query must not be retained in container logs.
logs=$(docker compose -p "$project" logs --no-color)
if printf '%s' "$logs" | python3 -c 'import sys; marker=sys.argv[1]; raise SystemExit(0 if marker in sys.stdin.read() else 1)' "$marker"; then
  printf 'Synthetic search query leaked into container logs\n' >&2
  exit 1
fi
printf 'QUERY_ABSENT_FROM_CONTAINER_LOGS=true\n'

cleanup
trap - EXIT INT TERM

if [ -n "$(docker ps -aq --filter "label=com.docker.compose.project=${project}")" ]; then
  printf 'Compose-owned containers remain after cleanup\n' >&2
  exit 1
fi
if docker network inspect "$network" >/dev/null 2>&1; then
  printf 'Compose-owned network remains after cleanup\n' >&2
  exit 1
fi
if docker volume ls -q --filter "label=com.docker.compose.project=${project}" | python3 -c 'import sys; raise SystemExit(0 if sys.stdin.read().strip() else 1)'; then
  printf 'Compose-owned volumes remain after cleanup\n' >&2
  exit 1
fi

printf 'SEARXNG_STACK_TEST_PASS\n'
