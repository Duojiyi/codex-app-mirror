#!/usr/bin/env bash
set -euo pipefail

tag="${1:-}"
checksums_path="${2:-SHA256SUMS.txt}"

if [[ -z "$tag" ]]; then
  echo "Usage: $0 <release-tag> [checksums-path]" >&2
  exit 2
fi
if [[ ! "$tag" =~ ^[A-Za-z0-9][A-Za-z0-9._-]{0,127}$ ]]; then
  echo "Invalid release tag '$tag'." >&2
  exit 1
fi

: "${GH_TOKEN:?GH_TOKEN is required}"
: "${GH_REPO:?GH_REPO is required}"

if [[ ! "$GH_REPO" =~ ^[A-Za-z0-9_.-]+/[A-Za-z0-9_.-]+$ ]]; then
  echo "Invalid GH_REPO '$GH_REPO'." >&2
  exit 1
fi
if [[ ! -f "$checksums_path" ]]; then
  echo "Missing checksums file: $checksums_path" >&2
  exit 1
fi

for command in gh jq curl python3; do
  command -v "$command" >/dev/null 2>&1 || {
    echo "Missing required command: $command" >&2
    exit 1
  }
done

urlencode_path_segment() {
  python3 - "$1" <<'PY'
from urllib.parse import quote
import sys

print(quote(sys.argv[1], safe="-._~"))
PY
}

server_url="${GITHUB_SERVER_URL:-https://github.com}"
server_url="${server_url%/}"
encoded_tag="$(urlencode_path_segment "$tag")"
release_base_url="$server_url/$GH_REPO/releases/download/$encoded_tag"
release_json="$(gh release view "$tag" --repo "$GH_REPO" --json assets,tagName,isDraft)"

jq -e --arg tag "$tag" '
  .tagName == $tag
  and .isDraft == false
  and (.assets | length) > 0
' <<<"$release_json" >/dev/null

declare -A expected_assets=()
checksum_entries=0
while IFS= read -r line || [[ -n "$line" ]]; do
  if [[ "$line" =~ ^[0-9a-fA-F]{64}[[:space:]]+(.+)$ ]]; then
    expected_assets["${BASH_REMATCH[1]}"]=1
    checksum_entries=$((checksum_entries + 1))
  fi
done < "$checksums_path"
checksums_asset="${checksums_path##*/}"
if [[ -z "$checksums_asset" || "$checksums_asset" == "." || "$checksums_asset" == ".." ]]; then
  echo "Invalid checksums asset path: $checksums_path" >&2
  exit 1
fi
expected_assets["$checksums_asset"]=1
expected_assets[status.png]=1

if [[ "$checksum_entries" -eq 0 ]]; then
  echo "No checksum entries found in $checksums_path." >&2
  exit 1
fi

declare -A actual_assets=()
while IFS= read -r asset; do
  [[ -n "$asset" ]] || continue
  actual_assets["$asset"]=1
done < <(jq -r '.assets[].name' <<<"$release_json")

missing_assets=()
for asset in "${!expected_assets[@]}"; do
  if [[ -z "${actual_assets[$asset]+present}" ]]; then
    missing_assets+=("$asset")
  fi
done
if [[ "${#missing_assets[@]}" -gt 0 ]]; then
  echo "Release $tag is missing assets listed by $checksums_path:" >&2
  printf '  %s\n' "${missing_assets[@]}" >&2
  exit 1
fi

for asset in "${!actual_assets[@]}"; do
  asset_url="$release_base_url/$(urlencode_path_segment "$asset")"
  echo "Checking $asset_url"
  curl -fsSIL \
    --retry 5 \
    --retry-delay 2 \
    --retry-all-errors \
    --connect-timeout 20 \
    --max-time 120 \
    "$asset_url" >/dev/null
done

echo "GitHub Release asset URLs verified: $tag (${#actual_assets[@]} assets)"
