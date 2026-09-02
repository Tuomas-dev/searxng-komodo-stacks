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
export ALLOWED_CIDR=127.0.0.1/32
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
[ "$ready" = true ]

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

# An allowlisted loopback request must return valid JSON and real results.
python3 - "$port" "$marker" <<'PY'
import json
import sys
import urllib.parse
import urllib.request
port, marker = sys.argv[1:]
query = f"OpenAI Hermes {marker}"
url = f"http://127.0.0.1:{port}/search?" + urllib.parse.urlencode({"q": query, "format": "json"})
with urllib.request.urlopen(url, timeout=30) as response:
    if response.status != 200:
        raise SystemExit(f"unexpected status {response.status}")
    payload = json.load(response)
results = payload.get("results")
if not isinstance(results, list) or not results:
    raise SystemExit("JSON search returned no results")
print(f"JSON_SEARCH_RESULTS={len(results)}")
PY

# A non-allowlisted container on the same network must be rejected with 403.
deny_output=$(docker run --rm \
  --network "$network" \
  --entrypoint sh \
  docker.io/library/caddy@sha256:4c6e91c6ed0e2fa03efd5b44747b625fec79bc9cd06ac5235a779726618e530d \
  -c 'wget -S -O /dev/null http://ingress:8080/healthz' 2>&1 || true)
python3 - "$deny_output" <<'PY'
import sys
text = sys.argv[1]
if "403" not in text:
    raise SystemExit("non-allowlisted request did not return HTTP 403")
print("NON_ALLOWLISTED_HTTP=403")
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
