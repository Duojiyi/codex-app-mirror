#!/usr/bin/env bash
set -euo pipefail

tmp_dir="$(mktemp -d)"
repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cleanup() {
  rm -rf "$tmp_dir"
}
trap cleanup EXIT

mkdir -p "$tmp_dir/bin"
cat > "$tmp_dir/release-state.json" <<'JSON'
{
  "tagName": "codex-app-1.2.3",
  "isDraft": false,
  "assets": [
    {"name": "status.png"},
    {"name": "release-manifest.json"},
    {"name": "SHA256SUMS.txt"},
    {"name": "OpenAI.Codex_1.2.3.4_x64__2p2nqsd0c76g0.Msix"},
    {"name": "Codex (arm64).dmg"}
  ]
}
JSON

cat > "$tmp_dir/SHA256SUMS.txt" <<'SUMS'
aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa  release-manifest.json
bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb  SHA256SUMS.txt
cccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccc  OpenAI.Codex_1.2.3.4_x64__2p2nqsd0c76g0.Msix
dddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddd  Codex (arm64).dmg
SUMS

cat > "$tmp_dir/bin/gh" <<'GH'
#!/usr/bin/env bash
set -euo pipefail

[[ "${1:-}" == "release" && "${2:-}" == "view" ]] || {
  echo "unexpected gh command: $*" >&2
  exit 1
}
cat "${GH_MOCK_STATE:?}"
GH
chmod +x "$tmp_dir/bin/gh"

cat > "$tmp_dir/bin/curl" <<'CURL'
#!/usr/bin/env bash
set -euo pipefail

printf '%s\n' "${!#}" >> "${CURL_LOG:?}"
CURL
chmod +x "$tmp_dir/bin/curl"

(
  cd "$tmp_dir"
  PATH="$tmp_dir/bin:$PATH" \
    GH_TOKEN=fixture \
    GH_REPO=Duojiyi/codex-app-mirror \
    GITHUB_SERVER_URL=https://github.com \
    GH_MOCK_STATE="$tmp_dir/release-state.json" \
    CURL_LOG="$tmp_dir/curl.log" \
    bash "$repo_root/scripts/verify-github-release-assets.sh" codex-app-1.2.3 SHA256SUMS.txt > output.txt

  test "$(wc -l < curl.log | tr -d '[:space:]')" = 5
  grep -F 'https://github.com/Duojiyi/codex-app-mirror/releases/download/codex-app-1.2.3/Codex%20%28arm64%29.dmg' curl.log
  grep -F 'GitHub Release asset URLs verified: codex-app-1.2.3 (5 assets)' output.txt

  jq 'del(.assets[] | select(.name == "status.png"))' release-state.json > missing-state.json
  set +e
  PATH="$tmp_dir/bin:$PATH" \
    GH_TOKEN=fixture \
    GH_REPO=Duojiyi/codex-app-mirror \
    GITHUB_SERVER_URL=https://github.com \
    GH_MOCK_STATE="$tmp_dir/missing-state.json" \
    CURL_LOG="$tmp_dir/curl.log" \
    bash "$repo_root/scripts/verify-github-release-assets.sh" codex-app-1.2.3 SHA256SUMS.txt > missing-output.txt 2>&1
  status=$?
  set -e
  test "$status" -ne 0
  grep -F 'Release codex-app-1.2.3 is missing assets listed by SHA256SUMS.txt' missing-output.txt

  jq 'del(.assets[] | select(.name == "SHA256SUMS.txt"))' release-state.json > missing-checksum-state.json
  set +e
  PATH="$tmp_dir/bin:$PATH" \
    GH_TOKEN=fixture \
    GH_REPO=Duojiyi/codex-app-mirror \
    GITHUB_SERVER_URL=https://github.com \
    GH_MOCK_STATE="$tmp_dir/missing-checksum-state.json" \
    CURL_LOG="$tmp_dir/curl.log" \
    bash "$repo_root/scripts/verify-github-release-assets.sh" codex-app-1.2.3 SHA256SUMS.txt > missing-checksum-output.txt 2>&1
  status=$?
  set -e
  test "$status" -ne 0
  grep -F 'SHA256SUMS.txt' missing-checksum-output.txt
)

echo "verify-github-release-assets fixture test PASS"
