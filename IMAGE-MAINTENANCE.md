# Docker image maintenance

## Keep human-readable version tags

Every successful image publication must maintain these multi-platform aliases:

- `latest`
- The exact `[package].version` from the published source's `Cargo.toml`, such as `0.40.0`
- `sha-<full source commit>`

The readable version is the Redlib base version, not an assertion that this fork is an official upstream release. A version alias can move when this fork publishes fixes without changing the base version. Use a digest for an immutable deployment. Preserve older version tags rather than deleting them during upgrades.

When integrating future upstream releases:

1. Check that `Cargo.toml` and `Cargo.lock` reflect the intended upstream package version.
2. Preserve the **Publish readable version from Cargo.toml** step in `.github/workflows/main-docker.yml`. Never replace readable tags with only Git SHAs.
3. Publish only after the Rust checks, native smoke tests, and vulnerability scans succeed for both architectures.
4. Confirm that the readable version tag resolves to the same manifest as the new SHA tag and includes `linux/amd64` and `linux/arm64`. `scripts/tag-image-version.sh` enforces this without rebuilding the image.
5. Keep Docker Hub's description version-free; maintain its tag policy in `DOCKERHUB.md`.

The tag helper rejects Cargo versions containing `+` build metadata because Docker tags cannot contain that character. Define an explicit mapping before introducing such versions; do not silently truncate the version.

## Backfill or repair a readable tag without rebuilding

Run the **Docker Hub version tag** workflow on `main`, passing the full source commit of an already-published image:

```sh
gh workflow run dockerhub-version.yml --repo taglia/redlib --ref main \
  -f revision=<full source commit>
```

It requires a successful `Docker Hub` CI run for that commit on `main`, reads `Cargo.toml` at that exact commit, checks the existing SHA-tagged multi-platform image, and publishes the readable alias using the existing manifest digest. It does not change `latest` or rebuild images. Be deliberate when selecting an older commit: this operation can move that version's alias backward.
