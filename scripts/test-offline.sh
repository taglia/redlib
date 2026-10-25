#!/usr/bin/env bash
# Deterministic suite. These upstream tests require live Reddit OAuth/API access;
# run `cargo test --locked -- --include-ignored` separately to exercise them.
set -euo pipefail
network_tests=(
  client::tests::test_rate_limit_check
  client::tests::test_default_subscriptions
  client::tests::test_localization_popular
  client::tests::test_obfuscated_share_link
  client::tests::test_private_sub
  client::tests::test_banned_sub
  client::tests::test_gated_sub
  oauth::tests::test_mobile_spoof_backend
  oauth::tests::test_generic_web_backend
  oauth::tests::test_oauth_client
  oauth::tests::test_oauth_client_refresh
  oauth::tests::test_oauth_token_exists
  oauth::tests::test_oauth_headers_len
  utils::tests::test_fetching_subreddit_quarantined
  utils::tests::test_fetching_nsfw_subreddit
  utils::tests::test_fetching_ws
  subreddit::tests::test_fetching_subreddit
  subreddit::tests::test_gated_and_quarantined
  user::tests::test_fetching_user
)
args=()
for test in "${network_tests[@]}"; do
  args+=(--skip "$test")
done
cargo test --locked --all-targets -- "${args[@]}" "$@"
