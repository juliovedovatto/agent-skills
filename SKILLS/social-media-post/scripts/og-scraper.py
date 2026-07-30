#!/usr/bin/env python3
"""Extract Open Graph metadata from a URL or raw HTML.

Usage:
    python3 og-scraper.py <URL>
    python3 og-scraper.py --html <FILE>
    cat page.html | python3 og-scraper.py --html -

Output (stdout only, compact JSON):
    {"url":"...","title":"...","description":"...","thumbnailUrl":"..."}
"""

import argparse
import json
import logging
import sys
from pathlib import Path

import metadata_parser


def _silence_noisy_loggers() -> None:
    """metadata-parser logs routine fetch details as errors; keep them off stderr."""
    # The package logger name has a historical typo (`metdata_parser`); cover both.
    logging.getLogger("metdata_parser").disabled = True
    logging.getLogger("metadata_parser").disabled = True
    logging.getLogger("urllib3").setLevel(logging.CRITICAL)
    logging.getLogger("requests").setLevel(logging.CRITICAL)
    logging.getLogger("charset_normalizer").setLevel(logging.CRITICAL)


def _empty_result(url: str = "") -> dict:
    return {"url": url, "title": "", "description": "", "thumbnailUrl": ""}


def _read_html_source(path: str) -> bytes:
    if path == "-":
        return sys.stdin.buffer.read()
    return Path(path).read_bytes()


def _extract_from_url(url: str) -> dict:
    parser = metadata_parser.MetadataParser(url=url)
    result = parser.parsed_result
    og = result.metadata.get("og", {})

    title = result.select_first_match("title", strategy=["og", "page"]) or url
    description = (
        result.select_first_match("description", strategy=["og", "meta"]) or ""
    )
    thumbnail = result.select_first_match("image", strategy=["og"]) or ""

    return {
        "url": url,
        "title": title,
        "description": description,
        "thumbnailUrl": thumbnail,
    }


def _extract_from_html(html: bytes, fallback_url: str = "") -> dict:
    parser = metadata_parser.MetadataParser(html=html)
    result = parser.parsed_result
    og = result.metadata.get("og", {})

    page_url = og.get("url") or fallback_url
    title = result.select_first_match("title", strategy=["og", "page"]) or page_url
    description = (
        result.select_first_match("description", strategy=["og", "meta"]) or ""
    )
    thumbnail = result.select_first_match("image", strategy=["og"]) or ""

    return {
        "url": page_url,
        "title": title,
        "description": description,
        "thumbnailUrl": thumbnail,
    }


def _parse_args(argv: list[str]) -> argparse.Namespace:
    parser = argparse.ArgumentParser(
        prog="og-scraper.py",
        description="Extract Open Graph metadata from a URL or raw HTML.",
    )
    parser.add_argument(
        "--html",
        dest="html_path",
        metavar="FILE",
        help="Parse raw HTML from FILE or '-' for stdin instead of fetching a URL.",
    )
    parser.add_argument(
        "url",
        nargs="?",
        help="URL to fetch and extract OG metadata from.",
    )
    return parser.parse_args(argv)


def main(argv: list[str] | None = None) -> int:
    _silence_noisy_loggers()
    args = _parse_args(argv if argv is not None else sys.argv[1:])

    try:
        if args.html_path is not None:
            html = _read_html_source(args.html_path)
            # A positional URL given alongside --html is accepted as the fallback
            # output URL when the HTML does not declare an og:url itself.
            data = _extract_from_html(html, fallback_url=args.url or "")
        else:
            if not args.url:
                print("Error: a URL is required", file=sys.stderr)
                return 2
            data = _extract_from_url(args.url)
    except Exception:
        # Graceful failure: never dump a traceback to stdout; emit valid JSON.
        data = _empty_result(args.url or "")

    print(json.dumps(data, ensure_ascii=False))
    return 0


if __name__ == "__main__":
    sys.exit(main())
