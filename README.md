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
- No Caddy access log is enabled, preventing query strings from entering proxy logs.
- SearXNG enables JSON output only, disables autocomplete, image proxy, public-instance mode, limiter, and metrics.
- Images are pinned by multi-architecture manifest digest.
- Containers drop capabilities, set `no-new-privileges`, apply resource limits, and rotate bounded runtime logs.

SearXNG is search-only in Hermes. Configure `web.search_backend: searxng`; select `web.extract_backend` independently.

## Validation

Run the repository-owned acceptance harness on an isolated Docker host:

```bash
./scripts/acceptance.sh
```

It renders Compose, starts an isolated project, proves health and JSON search, proves a non-allowlisted container gets HTTP 403, confirms SearXNG has no host port, checks that a synthetic query is absent from container logs, and verifies complete cleanup.
