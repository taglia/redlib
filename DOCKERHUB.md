# Unofficial Redlib Docker Image

A private Reddit front-end, built from reviewed Redlib source for **linux/amd64** and **linux/arm64**. This is an unofficial, personally maintained image, not an official upstream release.

- **Upstream project:** https://github.com/redlib-org/redlib
- **Image source and configuration:** https://github.com/taglia/redlib
- **Security review and limitations:** https://github.com/taglia/redlib/blob/main/SECURITY-REVIEW.md
- **License:** AGPL-3.0-only — https://github.com/taglia/redlib/blob/main/LICENSE

## Run

```sh
docker run -d --name redlib \
  -p 127.0.0.1:8080:8080 \
  --restart unless-stopped \
  tagliasteel/redlib:latest
```

Open http://localhost:8080. For public access, configure a reverse proxy with HTTPS.

The image runs as a nonroot user and includes a shell-free healthcheck. Configuration and Compose examples are available in the [repository README](https://github.com/taglia/redlib#readme).

## Tags and corresponding source

- `latest`: the most recently published multi-platform build; this tag changes over time.
- `<major>.<minor>.<patch>`: a readable version from the source's `Cargo.toml`. It tracks this fork's latest verified build of that version and may move when the fork receives fixes. It is not an official upstream release tag.
- `sha-<full commit>`: a build identified by its source commit.

Prefer an image digest for an immutable deployment. The image label `org.opencontainers.image.revision` identifies its exact source commit:

```sh
docker pull tagliasteel/redlib:latest
docker image inspect tagliasteel/redlib:latest \
  --format '{{index .Config.Labels "org.opencontainers.image.revision"}}'
```

View that commit at `https://github.com/taglia/redlib/tree/<full commit>`.

## Maintenance

Publication is gated by Rust checks, native image smoke tests, and HIGH/CRITICAL vulnerability scans. Scans are point-in-time checks, not a guarantee that an image has no vulnerabilities. Updates are best-effort; Reddit access can be restricted or unavailable.

This description is synchronized automatically from [DOCKERHUB.md](https://github.com/taglia/redlib/blob/main/DOCKERHUB.md). Versions belong in image metadata and tags, rather than this description.
