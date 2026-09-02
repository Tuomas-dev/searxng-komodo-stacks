# Dual SearXNG Komodo stacks

A single digest-pinned Compose definition deployed twice by Komodo:

- `searxng-private` — admits only the Private Hermes VM.
- `searxng-work` — admits only the Work Hermes VM (deny-all until that VM has a fixed address).

## Runtime contract

Komodo supplies a separate environment to each stack:

```dotenv
BIND_ADDRESS=<Swamp Systems LAN address>
PUBLISHED_PORT=<unique host port>
ALLOWED_CIDR=<single Hermes VM address>/32
SEARCH_SUBNET=<unique per-stack private Docker subnet>
SEARXNG_SECRET=<unique random value>
```

The values are not stored in Git. Each Komodo Stack uses its own Compose project name, named volume, explicitly non-overlapping bridge subnet, and environment file.

## Security properties

- SearXNG is never directly published; Caddy is the only host listener.
- Caddy admits loopback plus exactly one configured source CIDR and returns HTTP 403 to every other source.
- No Caddy access log is enabled. SearXNG uses Docker's `none` log driver because upstream-request failures are logged with full `q=` values at WARNING; health and sanitized JSON probes are the normal diagnostics.
- SearXNG enables JSON output only, disables autocomplete, image proxy, public-instance mode, limiter, and metrics.
- Images are pinned by multi-architecture manifest digest.
- Containers drop capabilities, set `no-new-privileges`, and apply resource limits; the ingress keeps bounded rotating diagnostic logs while SearXNG retains none.

SearXNG is search-only in Hermes. Configure `web.search_backend: searxng`; select `web.extract_backend` independently.

## Validation

Run the repository-owned acceptance harness on an isolated Docker host:

```bash
./scripts/acceptance.sh
```

It renders Compose, starts an isolated project, proves health and the JSON search response contract, proves a non-allowlisted request gets HTTP 403, confirms SearXNG has no host port, checks that a synthetic query is absent from container logs, and verifies complete cleanup. The isolated testbench may receive zero results because search engines commonly block datacenter egress; each live residential deployment must separately return at least one real result before acceptance.
