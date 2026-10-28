# Temporary dependency patch

`wreq-util/` is the crates.io release **3.0.0-rc.14**, distributed under the included Apache-2.0 license.

- Upstream: https://github.com/0x676e67/wreq-util
- Archive: https://static.crates.io/crates/wreq-util/wreq-util-3.0.0-rc.14.crate
- Verified archive SHA-256: `1d8d73c75be86fbde675988dbe5cb15f02567025c13f6ffab910361ad1ba6c89`
- The upstream archive's `Cargo.lock` and `.github/` maintenance files are omitted; the application's root lockfile and workflows control builds.
- The **only patch** is in the normalized `Cargo.toml`: `[dependencies.zstd].version` changes from `0.13.3` to `0.14.3`. `Cargo.toml.orig` remains the original upstream manifest for provenance. No Rust source is modified.

This removes the vulnerable zstd 0.13.x / zstd-safe 7.x dependency path used for TLS certificate compression. The HTTP decompression path already uses patched versions. See RUSTSEC-2026-0391, RUSTSEC-2026-0398, and RUSTSEC-2026-0403, plus the related zstd-safe unsoundness advisories.

The root `[patch.crates-io]` selects this copy. All Docker builders must copy `vendor/` before resolving dependencies. No advisory is suppressed for this patch.

## Removal

When a compatible upstream wreq-util release depends on `zstd >=0.14.3` and `zstd-safe >=8.2.0`, replace the patched dependency with that release, remove the root patch entry and this vendored copy, regenerate `Cargo.lock`, and rerun audit, offline tests, native image smoke checks, and both architecture vulnerability scans. Check `cargo tree -i zstd` to ensure no vulnerable parallel version remains. Do not migrate the HTTP client merely to remove this patch without reviewing compatibility.
