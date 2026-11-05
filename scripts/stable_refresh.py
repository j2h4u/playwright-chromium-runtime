#!/usr/bin/env python3
"""Refresh the pinned Chrome for Testing archives without changing Playwright."""

import hashlib
import json
import re
import sys
from pathlib import Path
from urllib.request import HTTPRedirectHandler, build_opener

MANIFEST = "https://googlechromelabs.github.io/chrome-for-testing/last-known-good-versions-with-downloads.json"
ARCHIVES = ("chrome-linux64.zip", "chrome-headless-shell-linux64.zip")
DOCKERFILE = Path("Dockerfile")


def one(pattern: str, text: str) -> str:
    matches = re.findall(pattern, text, re.MULTILINE)
    if len(matches) != 1:
        raise ValueError(f"expected one pin for {pattern}, found {len(matches)}")
    return matches[0]


def pins(text: str) -> tuple[str, str, str]:
    playwright = one(r"^ARG PLAYWRIGHT_VERSION=(\d+\.\d+\.\d+)$", text)
    runtime = one(r"^ARG RUNTIME_VERSION=(\d+\.\d+\.\d+-r[1-9]\d*)$", text)
    browser = one(r"^    PLAYWRIGHT_RUNTIME_CHROMIUM_VERSION=(\d+\.\d+\.\d+\.\d+) \\", text)
    if not runtime.startswith(playwright + "-r"):
        raise ValueError("runtime and Playwright pins disagree")
    for archive in ARCHIVES:
        one(r"^    echo '([0-9a-f]{64})  " + re.escape(archive) + r"' \| sha256sum -c -; \\", text)
    return playwright, runtime, browser


def stable(manifest: dict) -> tuple[str, dict[str, str]]:
    channel = manifest["channels"]["Stable"]
    version = channel["version"]
    if channel["channel"] != "Stable" or not re.fullmatch(r"\d+\.\d+\.\d+\.\d+", version):
        raise ValueError("invalid Stable version")
    urls = {}
    for artifact, archive in zip(("chrome", "chrome-headless-shell"), ARCHIVES):
        entries = [entry["url"] for entry in channel["downloads"][artifact] if entry["platform"] == "linux64"]
        expected = f"https://storage.googleapis.com/chrome-for-testing-public/{version}/linux64/{archive}"
        if entries != [expected]:
            raise ValueError(f"unexpected {artifact} download: {entries}")
        urls[archive] = expected
    return version, urls


class NoRedirect(HTTPRedirectHandler):
    def redirect_request(self, req, fp, code, msg, headers, newurl):
        raise ValueError(f"unexpected redirect to {newurl}")


def digest(url: str) -> str:
    hasher = hashlib.sha256()
    with build_opener(NoRedirect).open(url, timeout=60) as response:
        first = response.read(1024 * 1024)
        if not first.startswith(b"PK\x03\x04"):
            raise ValueError("download is not a ZIP archive")
        size = len(first)
        hasher.update(first)
        while chunk := response.read(1024 * 1024):
            size += len(chunk)
            hasher.update(chunk)
        if response.headers.get("Content-Length") and size != int(response.headers["Content-Length"]):
            raise ValueError("incomplete archive download")
    return hasher.hexdigest()


def update(text: str, version: str, hashes: dict[str, str]) -> str:
    _, runtime, current = pins(text)
    if tuple(map(int, version.split("."))) <= tuple(map(int, current.split("."))):
        raise ValueError("new browser must be newer than the current pin")
    if set(hashes) != set(ARCHIVES) or any(not re.fullmatch(r"[0-9a-f]{64}", h) for h in hashes.values()):
        raise ValueError("invalid archive hashes")
    prefix, revision = runtime.rsplit("-r", 1)
    text = text.replace(f"ARG RUNTIME_VERSION={runtime}\n", f"ARG RUNTIME_VERSION={prefix}-r{int(revision) + 1}\n")
    text = text.replace(f"PLAYWRIGHT_RUNTIME_CHROMIUM_VERSION={current} ", f"PLAYWRIGHT_RUNTIME_CHROMIUM_VERSION={version} ")
    for archive in ARCHIVES:
        pattern = r"(?<=echo ')[0-9a-f]{64}(?=  " + re.escape(archive) + r"')"
        text = re.sub(pattern, hashes[archive], text)
    pins(text)
    return text


def main() -> None:
    text = DOCKERFILE.read_text()
    playwright, runtime, current = pins(text)
    if sys.argv[1:] == ["pins"]:
        print(f"playwright={playwright}\nruntime={runtime}\nbrowser={current}")
        return
    if sys.argv[1:] != ["refresh"]:
        raise SystemExit("usage: stable_refresh.py pins|refresh")
    with build_opener(NoRedirect).open(MANIFEST, timeout=60) as response:
        version, urls = stable(json.load(response))
    if version == current:
        print("Stable browser unchanged")
        return
    if tuple(map(int, version.split("."))) < tuple(map(int, current.split("."))):
        raise ValueError("Stable browser is older than the current pin")
    hashes = {archive: digest(url) for archive, url in urls.items()}
    DOCKERFILE.write_text(update(text, version, hashes))
    print(f"Updated browser {current} -> {version}; SHA-256 calculated from downloaded archives")


if __name__ == "__main__":
    main()
