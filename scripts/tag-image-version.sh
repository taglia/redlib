#!/usr/bin/env bash
# Add a readable alias to an already-published, verified multi-platform image.
# Callers must gate this script on successful image verification/publication.
set -euo pipefail

revision="${1:?Usage: tag-image-version.sh FULL_REVISION [Cargo.toml]}"
cargo_file="${2:-Cargo.toml}"
image=tagliasteel/redlib
[[ "$revision" =~ ^[0-9a-f]{40}$ ]] || { echo 'Expected a full commit SHA' >&2; exit 1; }
version="$(python3 - "$cargo_file" <<'PY'
import re, sys, tomllib
with open(sys.argv[1], 'rb') as source:
    version = tomllib.load(source)['package']['version']
# Reject build metadata (+...), which Docker tags cannot represent directly.
if not re.fullmatch(r'[0-9]+\.[0-9]+\.[0-9]+(?:-[0-9A-Za-z.-]+)?', version) or len(version) > 128:
    raise SystemExit('Cargo version is not a supported Docker version tag')
print(version)
PY
)"

tmp="$(mktemp -d)"
trap 'rm -rf "$tmp"' EXIT
source="${image}:sha-${revision}"
docker buildx imagetools inspect --raw "$source" > "$tmp/source.json"
python3 - "$tmp/source.json" <<'PY'
import json, sys
with open(sys.argv[1]) as source:
    manifest = json.load(source)
platforms = sorted((m['platform']['os'], m['platform']['architecture']) for m in manifest['manifests'])
if platforms != [('linux', 'amd64'), ('linux', 'arm64')]:
    raise SystemExit('Expected exactly the verified amd64 and arm64 images')
PY
# Pin the source digest to avoid resolving a mutable tag again during promotion.
digest="sha256:$(sha256sum "$tmp/source.json" | cut -d ' ' -f 1)"
docker buildx imagetools create -t "${image}:${version}" "${image}@${digest}"
docker buildx imagetools inspect --raw "${image}:${version}" > "$tmp/version.json"
cmp "$tmp/source.json" "$tmp/version.json"
echo "Verified ${image}:${version} = ${source} (${digest})"
