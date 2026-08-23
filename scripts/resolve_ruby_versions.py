#!/usr/bin/env python3
"""Resolve stable Ruby releases from the official release page."""

import argparse
import re
import urllib.request


RELEASES_URL = "https://www.ruby-lang.org/en/downloads/releases/"
FALLBACK = {
    "2.7": ["2.7.0", "2.7.8"],
    "3.0": ["3.0.0", "3.0.6"],
    "3.1": ["3.1.0", "3.1.6"],
    "3.2": ["3.2.0", "3.2.11"],
    "3.3": ["3.3.0", "3.3.12"],
    "3.4": ["3.4.0", "3.4.10"],
    "4.0": ["4.0.0", "4.0.6"],
}

# Ruby 3.0.7 and 3.1.7 were released upstream without matching tags in the
# Docker Official Image. Use the newest published image for those lines.
DOCKER_LATEST = {
    "3.0": "3.0.6",
    "3.1": "3.1.6",
}


def version_key(version):
    return tuple(int(part) for part in version.split("."))


def parse_releases(text):
    versions = re.findall(r"Ruby\s+(\d+\.\d+\.\d+)(?![-a-zA-Z0-9])", text)
    return sorted(set(versions), key=version_key)


def fetch_releases():
    request = urllib.request.Request(RELEASES_URL, headers={"User-Agent": "ruby-version-benchmark/1"})
    with urllib.request.urlopen(request, timeout=30) as response:
        return parse_releases(response.read().decode("utf-8"))


def resolve(versions, lines, kinds):
    rows = []
    for line in lines:
        stable = [version for version in versions if version.startswith(line + ".")]
        if not stable and line in FALLBACK:
            stable = FALLBACK[line]
        stable.sort(key=version_key)
        if not stable:
            continue
        for kind in kinds:
            if kind == "first":
                version = stable[0]
            else:
                version = DOCKER_LATEST.get(line, stable[-1])
            rows.append((line, kind, version, f"ruby:{version}"))
    return rows


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--lines", default="4.0,3.4,3.3,3.2,3.1,3.0,2.7")
    parser.add_argument("--kinds", default="latest")
    parser.add_argument("--offline", action="store_true")
    args = parser.parse_args()
    try:
        versions = [] if args.offline else fetch_releases()
    except Exception:
        versions = []
    rows = resolve(versions, args.lines.split(","), args.kinds.split(","))
    for row in rows:
        print("\t".join(row))
    return 0 if rows else 1


if __name__ == "__main__":
    raise SystemExit(main())
