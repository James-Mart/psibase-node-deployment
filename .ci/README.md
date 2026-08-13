# CI

Verification that is not operator configuration lives here. `.ci/.env.ci`
supplies values so checks can render Compose and, later, stand the stack up
in isolation. Test-only knobs stay in this directory. Which psinode release
an operator runs is their choice; the pin below exists so CI is deterministic.
Do not copy it into `.env.template`.

Run the static checks from the repository root:

```bash
.ci/run-checks.sh
```

## Certificates

CI never contacts a real certificate authority or DNS provider. Traefik falls
back to its self-signed certificate, which is enough to exercise TLS
termination, host-based routing, and forward-auth.

Getting there is less obvious than it looks. Traefik reads static configuration
from exactly one source, in the order file, command-line flags, environment —
and stops at the first one that loads. The shipped deployment mounts
`traefik/traefik.yml`, so it always wins: neither
`TRAEFIK_CERTIFICATESRESOLVERS_CLOUDFLARE_ACME_CASERVER` nor the equivalent CLI
flag can move the ACME CA server, and both were tried. A bring-up run with the
environment variable set still reached Let's Encrypt and was turned away with a
`rejectedIdentifier` for `ci-node.invalid`.

So `docker-compose.ci.yml` refuses outbound HTTPS instead, with
`HTTPS_PROXY` pointed at a dead local port. ACME dies at the proxy connect,
before anything leaves the container, and the Cloudflare DNS challenge is never
reached. Traefik's routed backends are all plain HTTP, so request proxying is
unaffected. Overriding the certificate resolver would mean editing a file an
operator reads; this does not.

`.ci/bring-up.sh` asserts this rather than assuming it: Traefik's logs must show
issuance refused at the local proxy, and must not contain an ACME problem
document, which only a real CA can produce.

## Entrypoint mutation check

`.ci/entrypoint-mutation-check.sh` is the check on the check. Entrypoint branch
coverage is the load-bearing assertion in bring-up, so this script inverts the
first-run condition in `psinode-entrypoint.sh`, runs the full bring-up against
the mutated entrypoint, and fails unless bring-up fails naming the branch it
expected, the flags it expected, and the argv it found. The entrypoint is
restored on every exit path short of a SIGKILL.

It runs as its own CI job and takes about as long as a bring-up.

## Psinode image

`PSINODE_IMAGE` in `.ci/.env.ci` is `v0.25.0-pre` (published 2026-08-05),
pinned by digest. It is the newest `ghcr.io/gofractally/psinode` tag that
clears the bar this Story needs before bring-up exists: the image pulls,
`psinode --version` succeeds (`psinode 0.25.0`), and the flags
`psinode-entrypoint.sh` passes are accepted — `-p`, `-o`, `-l`,
`--database-cache-size`, `--pkcs11-module`, and `--p2p`.

Native `psinode --help` lists `-p`, `-l`, `--database-cache-size`, and
`--pkcs11-module`. `-o`/`--host` and `--p2p` were moved out of native help
([psibase#1511](https://github.com/gofractally/psibase/pull/1511),
[psibase#1515](https://github.com/gofractally/psibase/pull/1515)) and are
accepted as extra options handled in WASM. They are still the flags the
entrypoint passes.

If a later bring-up check fails on this tag, pick again rather than
weakening the bar.

## Upstream drift

The weekly (and manual `workflow_dispatch`) drift job re-runs bring-up
against a floating psinode tag so a new upstream image shows up in this
repository's CI rather than on an operator's host. It is non-blocking and
does not run on pull requests or pushes.

`ghcr.io/gofractally/psinode` does not publish `:latest`, `main`, or any
other moving alias — those tags return `manifest unknown`. The refs that
exist are version tags (`v0.25.0-pre`), arch-specific suffixes of those
tags, and commit-SHA snapshots. Commit SHAs are immutable builds, not a
"current release" pointer, so they are not floating.

Floating here means the newest multi-arch version tag matching
`vX.Y.Z` or `vX.Y.Z-pre`, resolved at job start from the registry's tag
list. `.ci/floating-psinode-image.sh` prints that reference. Today that
is `v0.25.0-pre`, the same tag the digest pin uses; when a newer version
tag appears, drift follows it without a pin change. The job logs the tag
and the digest it resolved so a red run is distinguishable from a
regression against the pin.

To run the same override locally:

```bash
PSINODE_IMAGE="$(.ci/floating-psinode-image.sh)"
export PSINODE_IMAGE
CI_ADMIN_PASSWORD="$(openssl rand -base64 24)" .ci/bring-up.sh
```

## Peers panel

The x-admin peers panel needs a psinode build that includes
[psibase#1987](https://github.com/gofractally/psibase/pull/1987), merged
2026-08-10. No published tag contains that merge. `v0.25.0-pre` is five
days earlier. CI on this pin cannot demonstrate a working peers panel.
Watch [psibase releases](https://github.com/gofractally/psibase/releases)
for a tag after that date.
