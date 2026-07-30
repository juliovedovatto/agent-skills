#!/usr/bin/env bash
#
# og-scraper.sh - Extract Open Graph metadata from a URL or raw HTML.
#
# Usage:
#   ./scripts/og-scraper.sh <URL>
#   ./scripts/og-scraper.sh --html <FILE>
#   cat page.html | ./scripts/og-scraper.sh --html -
#
# Output:
#   {"url":"...","title":"...","description":"...","thumbnailUrl":"..."}

set -euo pipefail

UV="/opt/homebrew/bin/uv"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# 1. Ensure `uv` is available.
if [[ ! -x "${UV}" ]]; then
  UV="$(command -v uv || true)"
fi
if [[ -z "${UV}" ]]; then
  echo "og-scraper: 'uv' not found" >&2
  exit 1
fi

# 2. Require at least one argument.
if [[ $# -eq 0 ]]; then
  cat >&2 <<'USAGE'
Usage:
  ./scripts/og-scraper.sh <URL>
  ./scripts/og-scraper.sh --html <FILE>
  cat page.html | ./scripts/og-scraper.sh --html -
USAGE
  exit 2
fi

# 3/4. Validate input depending on mode.
if [[ "$1" != "--html" ]]; then
  if [[ ! "$1" =~ ^https?://.+ ]]; then
    echo "og-scraper: invalid URL '$1'" >&2
    exit 2
  fi
else
  if [[ $# -lt 2 ]]; then
    echo "og-scraper: --html requires a file path or '-'" >&2
    exit 2
  fi
  if [[ "$2" != "-" && ! -r "$2" ]]; then
    echo "og-scraper: cannot read file '$2'" >&2
    exit 2
  fi
fi

exec "${UV}" run --with metadata-parser --python 3.12 "${SCRIPT_DIR}/og-scraper.py" "$@"
