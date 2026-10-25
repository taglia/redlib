#!/usr/bin/env bash
# Usage: scripts/update_hls_js.sh 1.7.3
# Review release notes/advisories before selecting a version. npm integrity is
# corruption protection, not proof that a maintainer account is uncompromised.
set -euo pipefail
version=${1:?usage: scripts/update_hls_js.sh <reviewed-version>}
root=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)
python3 - "$version" "$root/static/hls.min.js" <<'PY'
import base64
import hashlib
import io
import json
import pathlib
import re
import sys
import tarfile
import urllib.request

version, destination = sys.argv[1:]
if not re.fullmatch(r"\d+\.\d+\.\d+", version):
    raise SystemExit("Expected a stable x.y.z version")
with urllib.request.urlopen(f"https://registry.npmjs.org/hls.js/{version}", timeout=30) as response:
    metadata = json.load(response)
url = metadata["dist"]["tarball"]
if not url.startswith("https://registry.npmjs.org/hls.js/-/"):
    raise SystemExit("Unexpected tarball origin")
with urllib.request.urlopen(url, timeout=30) as response:
    data = response.read()
algorithm, expected = metadata["dist"]["integrity"].split("-", 1)
if algorithm != "sha512" or base64.b64encode(hashlib.sha512(data).digest()).decode() != expected:
    raise SystemExit("npm SHA-512 integrity verification failed")
with tarfile.open(fileobj=io.BytesIO(data), mode="r:gz") as archive:
    asset = archive.extractfile("package/dist/hls.min.js").read()
header = (
    "// @license http://www.apache.org/licenses/LICENSE-2.0 Apache-2.0\n"
    f"// @source https://github.com/video-dev/hls.js/tree/v{version}\n"
)
pathlib.Path(destination).write_bytes(header.encode() + asset)
print(f"Updated hls.js to {version}; npm SHA-512 verified")
PY
