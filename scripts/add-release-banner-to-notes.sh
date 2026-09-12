#!/usr/bin/env bash
set -euo pipefail

tag="${1:-}"
repository="${GH_REPO:-${GITHUB_REPOSITORY:-}}"
server_url="${GITHUB_SERVER_URL:-https://github.com}"
server_url="${server_url%/}"

if [[ -z "$tag" ]]; then
  echo "Usage: $0 <release-tag>" >&2
  exit 2
fi
if [[ ! "$tag" =~ ^[A-Za-z0-9][A-Za-z0-9._-]{0,127}$ ]]; then
  echo "Invalid release tag '$tag'." >&2
  exit 1
fi
if [[ -z "$repository" || ! "$repository" =~ ^[A-Za-z0-9_.-]+/[A-Za-z0-9_.-]+$ ]]; then
  echo "GH_REPO or GITHUB_REPOSITORY must contain owner/repository." >&2
  exit 1
fi

urlencode_path_segment() {
  python3 - "$1" <<'PY'
from urllib.parse import quote
import sys

print(quote(sys.argv[1], safe="-._~"))
PY
}

release_banner_url="$server_url/$repository/releases/download/$(urlencode_path_segment "$tag")/status.png"

tmp_dir="$(mktemp -d)"
cleanup() {
  rm -rf "$tmp_dir"
}
trap cleanup EXIT

body_path="$tmp_dir/body.md"
updated_path="$tmp_dir/body-with-banner.md"

gh release view "$tag" --repo "$repository" --json body --jq '.body' > "$body_path"

RELEASE_BANNER_URL="$release_banner_url" python3 - "$body_path" "$updated_path" <<'PY'
import os
import re
import sys
from pathlib import Path

source = Path(sys.argv[1])
target = Path(sys.argv[2])

banner_url = os.environ["RELEASE_BANNER_URL"]
banner = f"""<!-- release-banner:start -->
![Codex App Mirror]({banner_url})
<!-- release-banner:end -->
"""

body = source.read_text(encoding="utf-8")
body = re.sub(
    r"\A\s*<!-- release-banner:start -->.*?<!-- release-banner:end -->\s*",
    "",
    body,
    flags=re.DOTALL,
)

updated = banner + "\n" + body.lstrip()
target.write_text(updated.rstrip() + "\n", encoding="utf-8")
PY

if cmp -s "$body_path" "$updated_path"; then
  echo "Release banner already current in $tag."
  exit 0
fi

gh release edit "$tag" --repo "$repository" --notes-file "$updated_path"
echo "Added release banner to $tag."
