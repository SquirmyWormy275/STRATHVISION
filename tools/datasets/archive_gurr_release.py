"""Archive unmodified Gurr Academy source files in this public GitHub release.

Requires an authenticated GitHub CLI and the original Seagate volume. The
release remains a draft until every asset's remote SHA-256 matches the source.
Re-running skips matching assets and refuses to overwrite a mismatch.
"""

from __future__ import annotations

import argparse
import hashlib
import json
import re
import subprocess
import tempfile
from pathlib import Path

REPO = "SquirmyWormy275/STRATHVISION"
TAG = "original-footage-2026-11-24"
SUFFIXES = {".mov", ".mp4", ".m4v", ".avi", ".zip"}
MAX_ASSET_BYTES = 2 * 1024 * 1024 * 1024


def command(*args: str) -> str:
    return subprocess.check_output(args, text=True).strip()


def checksum(path: Path) -> str:
    digest = hashlib.sha256()
    with path.open("rb") as source:
        for block in iter(lambda: source.read(4 * 1024 * 1024), b""):
            digest.update(block)
    return digest.hexdigest()


def asset_name(relative: Path) -> str:
    name = relative.as_posix().replace("/", "__")
    return re.sub(r"[^A-Za-z0-9._-]+", "-", name)


def remote_assets(release_id: int) -> dict[str, dict]:
    rows = json.loads(
        command(
            "gh",
            "api",
            f"repos/{REPO}/releases/{release_id}/assets?per_page=100",
        )
    )
    return {row["name"]: row for row in rows}


def verify_remote(local: dict, remote: dict) -> None:
    if remote.get("state") != "uploaded":
        raise RuntimeError(f"Remote asset is not uploaded: {local['asset_name']}")
    if remote.get("size") != local["size_bytes"]:
        raise RuntimeError(f"Remote asset has wrong size: {local['asset_name']}")
    if remote.get("digest") != f"sha256:{local['sha256']}":
        raise RuntimeError(f"Remote asset has wrong or unavailable checksum: {local['asset_name']}")


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--source", type=Path, required=True, help="Original Gurr Academy directory")
    parser.add_argument("--manifest-out", type=Path, required=True)
    args = parser.parse_args()

    try:
        source = args.source.resolve(strict=True)
    except FileNotFoundError:
        raise SystemExit("The original Seagate footage is not connected") from None
    if not source.is_dir() or "Gurr Academy" != source.name:
        raise SystemExit("Expected the mounted original Gurr Academy directory")
    if not source.is_relative_to(Path("/run/media")):
        raise SystemExit("Source must be the mounted external drive, not a local substitute")

    files = sorted(path for path in source.rglob("*") if path.is_file())
    if not files or any(path.suffix.lower() not in SUFFIXES for path in files):
        raise SystemExit("Source is empty or contains an unexpected file type; review before archiving")
    if any(path.stat().st_size >= MAX_ASSET_BYTES for path in files):
        raise SystemExit("At least one file exceeds GitHub's per-asset release limit")
    names = [asset_name(path.relative_to(source)) for path in files]
    if len(set(names)) != len(names):
        raise SystemExit("Two source paths map to the same release asset name")

    # GitHub's lookup-by-tag endpoint returns 404 for draft releases, so list
    # authenticated releases and identify the existing draft by its tag.
    releases = json.loads(command("gh", "api", f"repos/{REPO}/releases?per_page=100"))
    release = next((row for row in releases if row["tag_name"] == TAG), None)
    if release is None:
        raise SystemExit(f"Missing draft release {TAG} on {REPO}")
    if not release["draft"] or release["target_commitish"] != "implementation":
        raise SystemExit("Expected the implementation-branch draft release")
    release_id = release["id"]
    catalog = {"format": "strathvision-original-footage-release/1", "repo": REPO, "tag": TAG, "files": []}
    with tempfile.TemporaryDirectory(prefix="strathvision-release-assets-") as staging:
        for index, path in enumerate(files, 1):
            relative = path.relative_to(source)
            row = {
                "relative_path": relative.as_posix(),
                "asset_name": asset_name(relative),
                "size_bytes": path.stat().st_size,
                "sha256": checksum(path),
            }
            print(f"[{index}/{len(files)}] {row['relative_path']}", flush=True)
            existing = remote_assets(release_id).get(row["asset_name"])
            if existing is None:
                link = Path(staging, row["asset_name"])
                link.symlink_to(path)
                subprocess.run(
                    ["gh", "release", "upload", TAG, str(link), "-R", REPO],
                    check=True,
                )
                existing = remote_assets(release_id).get(row["asset_name"])
            if existing is None:
                raise RuntimeError(f"Upload missing from GitHub: {row['asset_name']}")
            verify_remote(row, existing)
            catalog["files"].append(row)

    args.manifest_out.parent.mkdir(parents=True, exist_ok=True)
    args.manifest_out.write_text(json.dumps(catalog, indent=2) + "\n")
    print(f"Verified {len(files)} public release assets; manifest: {args.manifest_out}", flush=True)
    print("Release is still a draft; review and publish it after committing the manifest.", flush=True)


if __name__ == "__main__":
    main()
