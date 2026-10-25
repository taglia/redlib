# Update security review (2026-10-25)

## Scope and provenance

Reviewed upstream changes from `a4d36e954cf1bd64f209cd8868c5a29edc81b374`
to `ba116c1186f6b0f9d45f0ae50c827e13eb2f5ea2` (Redlib 0.40.0),
including application code, templates, lockfile sources, and build scripts.
The upstream tip is unsigned; this is a code/dependency review, not an assertion
that an upstream signature authenticates it. No new application-code blocker was
identified. This is not a comprehensive penetration test or a security guarantee.

The DNS change resolves `www.reddit.com` using Fastly's dual-stack alias while
retaining the original TLS/SNI hostname. It introduces an availability dependency
on that alias, but does not disable certificate checks. The comments-path rewrite
changes paths, not URL authorities.

## Findings and remediation

- Upstream's `h2` 0.3.27 is affected by
  [RUSTSEC-2026-0258](https://rustsec.org/advisories/RUSTSEC-2026-0258).
  Disable unused Hyper server HTTP/2 support, removing that dependency. Terminate
  public TLS/HTTP2 at a maintained reverse proxy; the application serves HTTP/1.1.
  Hyper stays on its last 0.14 release: a 1.x server/body API migration is a
  separate compatibility project, not an automatic dependency bump.
- Replace the retired YAML serializer and its unmaintained `unsafe-libyaml`
  dependency with the serialization-only feature of `serde-saphyr`.
- Retain `bincode` 1.3.3 for existing exported settings compatibility.
  [RUSTSEC-2025-0141](https://rustsec.org/advisories/RUSTSEC-2025-0141)
  is an unmaintained warning, not a reported vulnerability; version 3.0 is not a
  drop-in upgrade. Bound settings request bodies, decompression, and decoding.
  A future format migration should retain legacy import tests.
- Escape RSS permalink HTML attributes and avoid a panic on invalid HTML entities.
  RSS body HTML still originates at Reddit; consumers must sanitize feed HTML.
- Replace the download-of-`latest` binary Dockerfile with a locked source build.
  Pin multiarch Rust/runtime base indexes and CI actions; use a numeric nonroot
  user and include working CA certificates and healthcheck tools.
- Disable upstream Quay/crates.io/release jobs in this fork. Docker Hub publishing
  requires successful Rust checks and both architectures' smoke tests and scans.
  Publish the exact scanned image artifacts, not a second potentially different
  build. Public tags are `latest`, `sha-<full commit>`, and per-architecture SHA tags.
- Update bundled hls.js to 1.7.3 from its npm tarball, verifying npm's SHA-512
  integrity value before extracting the asset. Registry integrity protects against
  corruption, not a compromised maintainer account.

## Local validation results

- Formatting, Clippy (`--all-targets -D warnings`), and actionlint pass.
- Deterministic suite: 46 passed; 20 live-API tests filtered out.
- `cargo audit`: no known vulnerabilities; the documented bincode maintenance warning remains.
- hls.js 1.7.3: OSV query returned no advisories.
- Native debug build served `/settings`, `/info.yaml`, and a populated `/r/rust`
  page successfully (HTTP 200). This does not guarantee Reddit availability from
  GitHub runners or other deployment networks.
- Nix flake evaluation passes for both supported architectures. Full Nix build
  validation is separate from the canonical Docker publishing pipeline.

## Validation policy

`cargo audit` fails on known vulnerabilities. The retained bincode maintenance
warning is reported, not suppressed; it is not treated as a vulnerability.
Container scans fail on HIGH/CRITICAL findings, including unfixed findings.
No blanket vulnerability exclusions are configured.

`scripts/test-offline.sh` explicitly lists upstream tests requiring live Reddit
OAuth/API access. They are excluded from the deterministic CI gate; all other
unit tests run. Use `cargo test --locked -- --include-ignored` for the complete
live suite. A green offline suite is not proof that Reddit will accept requests
from a particular deployment IP.

The Docker Hub workflow builds natively on x86_64 and aarch64 GitHub runners,
checks the nonroot configuration and `/settings`, scans the image, transfers it
using immutable workflow artifacts, and publishes only from this fork's `main`.
GitHub secrets are never needed by pull-request verification jobs.

Docker image attestations are not claimed: the artifact-transfer approach retains
exact scanned image bytes but does not currently attach signed provenance/SBOMs.
Review automated dependency update PRs rather than automatically merging them.
