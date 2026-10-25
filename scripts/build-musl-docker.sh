#!/usr/bin/env bash
set -euo pipefail

target=${1:?usage: scripts/build-musl-docker.sh <rust-target>}

case "$target" in
  x86_64-unknown-linux-musl)
    cross_image=x86_64-musl@sha256:ce75e9174325d4fbb3de85c309e2d7ca29f7500169bc4b5d2c611ff7e86d549a
    cross_gnu_packages=
    bindgen_args=
    ;;
  aarch64-unknown-linux-musl)
    cross_image=aarch64-musl@sha256:ecae5dd62d1c938c14f8071d36c16fa699860aace03bfb5284fb1216474d2643
    cross_gnu_packages="gcc-aarch64-linux-gnu g++-aarch64-linux-gnu"
    bindgen_args=
    ;;
  armv7-unknown-linux-musleabihf)
    cross_image=armv7-musleabihf@sha256:714d7529ed9098699cc13abade83c565e6a946e53975c108089a8cd3b43cb871
    cross_gnu_packages="gcc-arm-linux-gnueabihf g++-arm-linux-gnueabihf"
    bindgen_args="--target=arm-linux-gnueabihf --sysroot=/usr/arm-linux-gnueabihf"
    ;;
  *)
    echo "unsupported musl target: $target" >&2
    exit 2
    ;;
esac

image="redlib-builder:${target}"
progress=${DOCKER_BUILD_PROGRESS:-auto}
printf '\n==> Building %s with Docker (progress: %s)\n' "$target" "$progress"
docker build \
  --progress="$progress" \
  --target builder \
  --build-arg "RUST_CROSS_IMAGE=${cross_image}" \
  --build-arg "RUST_TARGET=${target}" \
  --build-arg "CROSS_GNU_PACKAGES=${cross_gnu_packages}" \
  --build-arg "BINDGEN_EXTRA_CLANG_ARGS=${bindgen_args}" \
  --file Dockerfile.alpine \
  --tag "$image" \
  .

artifact="target/${target}/release/redlib"
mkdir -p "target/${target}/release"
printf '\n==> Extracting %s binary\n' "$target"
docker run --rm \
  --entrypoint /bin/bash \
  --volume "$PWD/target/${target}/release:/out" \
  "$image" \
  -lc "cp /redlib/target/${target}/release/redlib /out/redlib"
test -s "$artifact"
echo "Built ${artifact} with Docker."
