#!/usr/bin/env python3
"""Upload a tagged macOS build as a GitHub prerelease using Git's credential helper."""
import json
import os
from pathlib import Path
import re
import subprocess
import sys
import urllib.parse
import urllib.request

root = Path(__file__).resolve().parents[1]
version = sys.argv[1] if len(sys.argv) > 1 else "0.1.0"
if not re.fullmatch(r"\d+\.\d+\.\d+", version):
    raise SystemExit("Expected a semantic version")
repo = "vivamau/MDreader"
tag = "v" + version
origin = subprocess.check_output(["git", "remote", "get-url", "origin"], cwd=root, text=True).strip()
if origin != f"https://github.com/{repo}.git":
    raise SystemExit("Unexpected origin; refusing to publish")
commit = subprocess.check_output(["git", "rev-parse", tag + "^{commit}"], cwd=root, text=True).strip()
assets = [root / "dist" / f"MDReader-{version}-macOS-universal.dmg"]
assets.append(Path(str(assets[0]) + ".sha256"))
for asset in assets:
    if not asset.is_file():
        raise SystemExit(f"Missing asset: {asset.name}")
credential = subprocess.run(
    ["git", "credential", "fill"], input=f"protocol=https\nhost=github.com\npath={repo}.git\n\n",
    cwd=root, capture_output=True, text=True, check=True,
    env={**os.environ, "GIT_TERMINAL_PROMPT": "0"})
fields = dict(line.split("=", 1) for line in credential.stdout.splitlines() if "=" in line)
token = fields.get("password")
if not token:
    raise SystemExit("GitHub authentication is required")

def request(url, method="GET", data=None, content_type="application/json"):
    headers = {"Authorization": "Bearer " + token, "Accept": "application/vnd.github+json",
               "User-Agent": "MDReader-release", "Content-Type": content_type}
    req = urllib.request.Request(url, data=data, headers=headers, method=method)
    with urllib.request.urlopen(req, timeout=120) as response:
        return json.load(response)

api = f"https://api.github.com/repos/{repo}"
remote_commit = request(api + "/commits/" + tag)["sha"]
if remote_commit != commit:
    raise SystemExit("Push the exact release tag before publishing")
# GitHub rejects duplicate tags/releases; never replace an existing release's assets.
release = request(api + "/releases", "POST", json.dumps({
    "tag_name": tag, "target_commitish": commit, "name": "MDReader " + version,
    "body": (root / "RELEASE_NOTES.md").read_text(), "draft": True, "prerelease": True
}).encode())
print("Created draft release", release["id"], flush=True)
for asset in assets:
    upload = release["upload_url"].split("{")[0] + "?name=" + urllib.parse.quote(asset.name)
    result = request(upload, "POST", asset.read_bytes(), "application/octet-stream")
    if result["size"] != asset.stat().st_size:
        raise SystemExit("Upload size mismatch; release left as draft")
    print("Uploaded", asset.name, flush=True)
result = request(api + "/releases/" + str(release["id"]), "PATCH", b'{"draft":false}')
print(result["html_url"])
