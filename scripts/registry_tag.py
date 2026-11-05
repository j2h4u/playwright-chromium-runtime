#!/usr/bin/env python3
"""Report whether a runtime tag exists; errors never count as absence."""

import json
import re
import sys
from urllib.error import HTTPError
from urllib.request import Request, urlopen

def main() -> None:
    name = "j2h4u/playwright-chromium-runtime"
    tag = sys.argv[1]
    if not re.fullmatch(r"v\d+\.\d+\.\d+-r[1-9]\d*", tag):
        raise SystemExit("invalid release tag")
    with urlopen(f"https://ghcr.io/token?service=ghcr.io&scope=repository:{name}:pull", timeout=30) as response:
        token = json.load(response)["token"]
    request = Request(
        f"https://ghcr.io/v2/{name}/manifests/{tag}",
        method="HEAD",
        headers={"Authorization": f"Bearer {token}", "Accept": "application/vnd.oci.image.index.v1+json, application/vnd.oci.image.manifest.v1+json, application/vnd.docker.distribution.manifest.v2+json, application/vnd.docker.distribution.manifest.list.v2+json"},
    )
    try:
        with urlopen(request, timeout=30):
            print(f"{tag} exists")
    except HTTPError as error:
        if error.code != 404:
            raise
        print(f"{tag} does not exist")
        raise SystemExit(3) from error


if __name__ == "__main__":
    main()
