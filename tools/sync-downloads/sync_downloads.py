#!/usr/bin/env python3
# Copyright (c) 2026 VitruvianSoftware
#
# Permission is hereby granted, free of charge, to any person obtaining a copy
# of this software and associated documentation files (the "Software"), to deal
# in the Software without restriction, including without limitation the rights
# to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
# copies of the Software, and to permit persons to whom the Software is
# furnished to do so, subject to the following conditions:
#
# The above copyright notice and this permission notice shall be included in
# all copies or substantial portions of the Software.
#
# THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
# IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
# FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
# AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
# LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
# OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE
# SOFTWARE.

"""Synchronizes the downloads catalog (apps/web/vitruviansoftware-dev/_data/downloads.yml)

with the latest published GitHub Releases across both standalone mirrored repositories
and monorepo package release tags in vitruvian-core.
"""

import argparse
import difflib
import json
import os
import re
import subprocess
import sys
import urllib.request
import urllib.error

DEFAULT_CATALOG = "apps/web/vitruviansoftware-dev/_data/downloads.yml"


def fetch_json(endpoint, token=None):
    """Fetch GitHub API endpoint using gh CLI if available, otherwise urllib."""
    if subprocess.run(["which", "gh"], capture_output=True).returncode == 0:
        res = subprocess.run(["gh", "api", endpoint], capture_output=True, text=True)
        if res.returncode == 0:
            return json.loads(res.stdout)

    url = f"https://api.github.com/{endpoint.lstrip('/')}"
    headers = {"User-Agent": "vitruvian-sync-downloads"}
    auth_token = token or os.environ.get("GH_TOKEN") or os.environ.get("GITHUB_TOKEN")
    if auth_token:
        headers["Authorization"] = f"token {auth_token}"

    req = urllib.request.Request(url, headers=headers)
    try:
        with urllib.request.urlopen(req, timeout=15) as resp:
            return json.loads(resp.read().decode("utf-8"))
    except Exception as e:
        print(f"Warning: Failed to fetch {url}: {e}", file=sys.stderr)
        return None


def parse_semver(tag):
    """Extract (major, minor, patch) from a tag string."""
    m = re.search(r"(\d+)\.(\d+)(?:\.(\d+))?", tag)
    if m:
        return (int(m.group(1)), int(m.group(2)), int(m.group(3) or 0))
    return (0, 0, 0)


def format_size(bytes_val):
    """Formats file size into standard human-readable units (e.g. 4.0 MB, 994 KB)."""
    if bytes_val < 1024 * 1024:
        return f"{round(bytes_val / 1024)} KB"
    mb = bytes_val / (1024 * 1024)
    # If integer, format as X MB, else X.X MB
    return f"{mb:.1f} MB" if mb < 10 or (mb * 10) % 10 != 0 else f"{int(mb)} MB"


def get_latest_release(repo, tag_prefix=None, token=None):
    """Discovers the latest non-prerelease Release object for a given repo or tag prefix."""
    if not tag_prefix:
        data = fetch_json(f"repos/{repo}/releases/latest", token=token)
        if data and not data.get("prerelease"):
            return data

    # Multi-component monorepo or prefix search
    refs = fetch_json(
        f"repos/{repo}/git/matching-refs/tags/{tag_prefix or ''}", token=token
    )
    if not refs:
        # Fallback to listing releases
        releases = fetch_json(f"repos/{repo}/releases?per_page=50", token=token)
        if releases:
            for r in releases:
                if not r.get("prerelease") and (
                    not tag_prefix or r.get("tag_name", "").startswith(tag_prefix)
                ):
                    return r
        return None

    valid_tags = []
    for r in refs:
        ref_name = r.get("ref", "").replace("refs/tags/", "")
        if "beta" in ref_name.lower():
            continue
        if tag_prefix and not ref_name.startswith(tag_prefix):
            continue
        valid_tags.append(ref_name)

    if not valid_tags:
        return None

    valid_tags.sort(key=parse_semver, reverse=True)
    latest_tag = valid_tags[0]
    return fetch_json(f"repos/{repo}/releases/tags/{latest_tag}", token=token)


def sync_catalog(catalog_path, dry_run=False, check=False, token=None):
    if not os.path.exists(catalog_path):
        print(f"Error: Catalog file not found at {catalog_path}", file=sys.stderr)
        return 1

    with open(catalog_path, "r", encoding="utf-8") as f:
        content = f.read()

    original_content = content
    updated_content = content

    print("=== DISCOVERING LATEST RELEASES ===")

    # 1. NexusAgent (Standalone repo: VitruvianSoftware/nexus-agent)
    rel_nexus = get_latest_release("VitruvianSoftware/nexus-agent", token=token)
    if rel_nexus:
        tag = rel_nexus.get("tag_name", "").lstrip("v")
        print(f"✓ NexusAgent: v{tag}")
        # Update version under nexus-agent block
        # Replace version: "..." right after id: nexus-agent
        updated_content = re.sub(
            r'(id:\s*nexus-agent[\s\S]*?version:\s*")[^"]+(")',
            rf"\g<1>{tag}\g<2>",
            updated_content,
            count=1,
        )
        # Update asset URLs and sizes
        for asset in rel_nexus.get("assets", []):
            name = asset.get("name", "")
            if name.endswith(".sha256") or name.endswith(".sig"):
                continue
            size_str = format_size(asset.get("size", 0))
            url = asset.get("browser_download_url", "")
            if "arm64.dmg" in name:
                updated_content = re.sub(
                    r"(label:\s*Apple Silicon DMG[\s\S]*?url:\s*)[^\n]+([\s\S]*?size:\s*)[^\n]+",
                    rf"\g<1>{url}\g<2>{size_str}",
                    updated_content,
                    count=1,
                )
            elif "universal.dmg" in name:
                updated_content = re.sub(
                    r"(label:\s*Universal DMG[\s\S]*?url:\s*)[^\n]+([\s\S]*?size:\s*)[^\n]+",
                    rf"\g<1>{url}\g<2>{size_str}",
                    updated_content,
                    count=1,
                )
            elif "x86_64.dmg" in name:
                updated_content = re.sub(
                    r"(label:\s*Intel x86_64 DMG[\s\S]*?url:\s*)[^\n]+([\s\S]*?size:\s*)[^\n]+",
                    rf"\g<1>{url}\g<2>{size_str}",
                    updated_content,
                    count=1,
                )
            elif "universal.zip" in name:
                updated_content = re.sub(
                    r"(label:\s*Universal ZIP[\s\S]*?url:\s*)[^\n]+([\s\S]*?size:\s*)[^\n]+",
                    rf"\g<1>{url}\g<2>{size_str}",
                    updated_content,
                    count=1,
                )

    # 2. Vitruvian Desktop (Monorepo: vitruvian-v*)
    rel_vitruvian = get_latest_release(
        "VitruvianSoftware/vitruvian-core", tag_prefix="vitruvian-v", token=token
    )
    if rel_vitruvian:
        tag = rel_vitruvian.get("tag_name", "").replace("vitruvian-v", "")
        print(f"✓ Vitruvian Desktop: v{tag}")
        updated_content = re.sub(
            r'(id:\s*vitruvian-desktop[\s\S]*?version:\s*")[^"]+(")',
            rf"\g<1>{tag}\g<2>",
            updated_content,
            count=1,
        )
        has_vitruvian_universal_dmg = any(
            "universal.dmg" in a.get("name", "") for a in rel_vitruvian.get("assets", [])
        )
        for asset in rel_vitruvian.get("assets", []):
            name = asset.get("name", "")
            if name.endswith(".sha256") or name.endswith(".sig"):
                continue
            size_str = format_size(asset.get("size", 0))
            url = asset.get("browser_download_url", "")
            if "arm64.dmg" in name:
                updated_content = re.sub(
                    r"(id:\s*vitruvian-desktop[\s\S]*?label:\s*Apple Silicon DMG[\s\S]*?url:\s*)[^\n]+([\s\S]*?size:\s*)[^\n]+",
                    rf"\g<1>{url}\g<2>{size_str}",
                    updated_content,
                    count=1,
                )
            elif "universal.dmg" in name:
                updated_content = re.sub(
                    r"(id:\s*vitruvian-desktop[\s\S]*?label:\s*Universal DMG[\s\S]*?url:\s*)[^\n]+([\s\S]*?size:\s*)[^\n]+",
                    rf"\g<1>{url}\g<2>{size_str}",
                    updated_content,
                    count=1,
                )
            elif not has_vitruvian_universal_dmg and name.endswith(".dmg") and "arm64" not in name and "x86_64" not in name and "beta" not in name:
                updated_content = re.sub(
                    r"(id:\s*vitruvian-desktop[\s\S]*?label:\s*Universal DMG[\s\S]*?url:\s*)[^\n]+([\s\S]*?size:\s*)[^\n]+",
                    rf"\g<1>{url}\g<2>{size_str}",
                    updated_content,
                    count=1,
                )
            elif "x86_64.dmg" in name:
                updated_content = re.sub(
                    r"(id:\s*vitruvian-desktop[\s\S]*?label:\s*Intel x86_64 DMG[\s\S]*?url:\s*)[^\n]+([\s\S]*?size:\s*)[^\n]+",
                    rf"\g<1>{url}\g<2>{size_str}",
                    updated_content,
                    count=1,
                )
            elif "universal.zip" in name:
                updated_content = re.sub(
                    r"(id:\s*vitruvian-desktop[\s\S]*?label:\s*Universal ZIP[\s\S]*?url:\s*)[^\n]+([\s\S]*?size:\s*)[^\n]+",
                    rf"\g<1>{url}\g<2>{size_str}",
                    updated_content,
                    count=1,
                )

    # 3. HomeSpeaker (Monorepo: home-speaker-v*)
    rel_speaker = get_latest_release(
        "VitruvianSoftware/vitruvian-core", tag_prefix="home-speaker-v", token=token
    )
    if rel_speaker:
        tag = rel_speaker.get("tag_name", "").replace("home-speaker-v", "")
        print(f"✓ HomeSpeaker: v{tag}")
        updated_content = re.sub(
            r'(id:\s*home-speaker[\s\S]*?version:\s*")[^"]+(")',
            rf"\g<1>{tag}\g<2>",
            updated_content,
            count=1,
        )
        has_speaker_universal_zip = any(
            "universal.zip" in a.get("name", "") for a in rel_speaker.get("assets", [])
        )
        for asset in rel_speaker.get("assets", []):
            name = asset.get("name", "")
            if name.endswith(".sha256") or name.endswith(".sig"):
                continue
            size_str = format_size(asset.get("size", 0))
            url = asset.get("browser_download_url", "")
            if "arm64.dmg" in name:
                updated_content = re.sub(
                    r"(id:\s*home-speaker[\s\S]*?label:\s*Apple Silicon DMG[\s\S]*?url:\s*)[^\n]+([\s\S]*?size:\s*)[^\n]+",
                    rf"\g<1>{url}\g<2>{size_str}",
                    updated_content,
                    count=1,
                )
            elif "universal.dmg" in name:
                updated_content = re.sub(
                    r"(id:\s*home-speaker[\s\S]*?label:\s*Universal DMG[\s\S]*?url:\s*)[^\n]+([\s\S]*?size:\s*)[^\n]+",
                    rf"\g<1>{url}\g<2>{size_str}",
                    updated_content,
                    count=1,
                )
            elif "x86_64.dmg" in name:
                updated_content = re.sub(
                    r"(id:\s*home-speaker[\s\S]*?label:\s*Intel x86_64 DMG[\s\S]*?url:\s*)[^\n]+([\s\S]*?size:\s*)[^\n]+",
                    rf"\g<1>{url}\g<2>{size_str}",
                    updated_content,
                    count=1,
                )
            elif "universal.zip" in name:
                updated_content = re.sub(
                    r"(id:\s*home-speaker[\s\S]*?label:\s*Universal ZIP[\s\S]*?url:\s*)[^\n]+([\s\S]*?size:\s*)[^\n]+",
                    rf"\g<1>{url}\g<2>{size_str}",
                    updated_content,
                    count=1,
                )
            elif not has_speaker_universal_zip and name.endswith("-macOS.zip"):
                updated_content = re.sub(
                    r"(id:\s*home-speaker[\s\S]*?label:\s*Universal ZIP[\s\S]*?url:\s*)[^\n]+([\s\S]*?size:\s*)[^\n]+",
                    rf"\g<1>{url}\g<2>{size_str}",
                    updated_content,
                    count=1,
                )

    # 4. devx (Standalone repo: VitruvianSoftware/devx)
    rel_devx = get_latest_release("VitruvianSoftware/devx", token=token)
    if rel_devx:
        tag = rel_devx.get("tag_name", "").lstrip("v")
        print(f"✓ devx: v{tag}")
        updated_content = re.sub(
            r'(id:\s*devx[\s\S]*?version:\s*")[^"]+(")',
            rf"\g<1>{tag}\g<2>",
            updated_content,
            count=1,
        )

    # 5. homelab (Standalone repo: VitruvianSoftware/homelab)
    rel_homelab = get_latest_release("VitruvianSoftware/homelab", token=token)
    if rel_homelab:
        tag = rel_homelab.get("tag_name", "").lstrip("v")
        print(f"✓ homelab: v{tag}")
        updated_content = re.sub(
            r'(id:\s*homelab[\s\S]*?version:\s*")[^"]+(")',
            rf"\g<1>{tag}\g<2>",
            updated_content,
            count=1,
        )

    # 6. gravastar-mouse (Monorepo: gravastar-mouse-v*)
    rel_mouse = get_latest_release(
        "VitruvianSoftware/vitruvian-core", tag_prefix="gravastar-mouse-v", token=token
    )
    if rel_mouse:
        tag_name = rel_mouse.get("tag_name", "")
        ver = tag_name.replace("gravastar-mouse-v", "")
        print(f"✓ gravastar-mouse: v{ver}")
        updated_content = re.sub(
            r'(id:\s*gravastar-mouse[\s\S]*?version:\s*")[^"]+(")',
            rf"\g<1>{ver}\g<2>",
            updated_content,
            count=1,
        )
        updated_content = re.sub(
            r"(id:\s*gravastar-mouse[\s\S]*?releases_url:\s*https://github.com/VitruvianSoftware/vitruvian-core/releases/tag/)[^\n]+",
            rf"\g<1>{tag_name}",
            updated_content,
            count=1,
        )

    # 7. esp32-s3 (Monorepo: esp32-s3-v*)
    rel_esp = get_latest_release(
        "VitruvianSoftware/vitruvian-core", tag_prefix="esp32-s3-v", token=token
    )
    if rel_esp:
        tag_name = rel_esp.get("tag_name", "")
        ver = tag_name.replace("esp32-s3-v", "")
        print(f"✓ esp32-s3: v{ver}")
        updated_content = re.sub(
            r'(id:\s*esp32-s3[\s\S]*?version:\s*")[^"]+(")',
            rf"\g<1>{ver}\g<2>",
            updated_content,
            count=1,
        )
        updated_content = re.sub(
            r"(id:\s*esp32-s3[\s\S]*?releases_url:\s*https://github.com/VitruvianSoftware/vitruvian-core/releases/tag/)[^\n]+",
            rf"\g<1>{tag_name}",
            updated_content,
            count=1,
        )
        for asset in rel_esp.get("assets", []):
            name = asset.get("name", "")
            size_str = format_size(asset.get("size", 0))
            url = asset.get("browser_download_url", "")
            if name == "esp32-s3-mac-controller.zip":
                updated_content = re.sub(
                    r"(label:\s*Mac Controller ZIP[\s\S]*?url:\s*)[^\n]+([\s\S]*?size:\s*)[^\n]+",
                    rf"\g<1>{url}\g<2>{size_str}",
                    updated_content,
                    count=1,
                )
            elif name == "firmware.bin":
                updated_content = re.sub(
                    r"(label:\s*Firmware Binary[\s\S]*?url:\s*)[^\n]+([\s\S]*?size:\s*)[^\n]+",
                    rf"\g<1>{url}\g<2>{size_str}",
                    updated_content,
                    count=1,
                )
            elif name == "bootloader.bin":
                updated_content = re.sub(
                    r"(label:\s*Bootloader Binary[\s\S]*?url:\s*)[^\n]+([\s\S]*?size:\s*)[^\n]+",
                    rf"\g<1>{url}\g<2>{size_str}",
                    updated_content,
                    count=1,
                )
            elif name == "partitions.bin":
                updated_content = re.sub(
                    r"(label:\s*Partition Table[\s\S]*?url:\s*)[^\n]+([\s\S]*?size:\s*)[^\n]+",
                    rf"\g<1>{url}\g<2>{size_str}",
                    updated_content,
                    count=1,
                )

    if original_content == updated_content:
        print("\nAll package versions and download URLs are already up to date.")
        return 0

    diff = difflib.unified_diff(
        original_content.splitlines(keepends=True),
        updated_content.splitlines(keepends=True),
        fromfile=f"a/{catalog_path}",
        tofile=f"b/{catalog_path}",
    )
    diff_text = "".join(diff)

    if check:
        print("\nCatalog is out of date! Diff:")
        print(diff_text)
        return 1

    if dry_run:
        print("\nDry-run mode. Proposed diff:")
        print(diff_text)
        return 0

    with open(catalog_path, "w", encoding="utf-8") as f:
        f.write(updated_content)

    print(f"\nSuccessfully updated {catalog_path}")
    return 0


def main():
    parser = argparse.ArgumentParser(
        description="Synchronize vitruviansoftware.dev downloads catalog with latest releases"
    )
    parser.add_argument(
        "--file",
        default=DEFAULT_CATALOG,
        help=f"Path to downloads.yml (default: {DEFAULT_CATALOG})",
    )
    parser.add_argument(
        "--dry-run", action="store_true", help="Print diff without modifying file"
    )
    parser.add_argument(
        "--check", action="store_true", help="Exit 1 if catalog is out of date"
    )
    parser.add_argument(
        "--token", help="GitHub token for API queries (or uses ambient gh / GH_TOKEN)"
    )
    args = parser.parse_args()

    # Locate relative to repo root if path is not absolute
    catalog_path = args.file
    if not os.path.isabs(catalog_path):
        root = os.environ.get("BUILD_WORKSPACE_DIRECTORY")
        if not root:
            root = subprocess.run(
                ["git", "rev-parse", "--show-toplevel"], capture_output=True, text=True
            ).stdout.strip()
        if root:
            catalog_path = os.path.join(root, catalog_path)

    sys.exit(
        sync_catalog(
            catalog_path, dry_run=args.dry_run, check=args.check, token=args.token
        )
    )


if __name__ == "__main__":
    main()
