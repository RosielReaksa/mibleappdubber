#!/usr/bin/env python3
"""Package a self-hosted Android APK update and, when possible, its delta."""

from __future__ import annotations

import argparse
import hashlib
import json
import os
import shutil
import sys
import tempfile
from pathlib import Path

try:
    import bsdiff4
except ImportError as exc:  # pragma: no cover - exercised by the CLI
    raise SystemExit(
        "Missing bsdiff4. Install the release helper dependency with: "
        "python -m pip install -r tools/update-requirements.txt"
    ) from exc


# 2013 is the first build that contains the delta-capable updater. Earlier
# builds ignore patch metadata and must receive the ordinary full APK.
DELTA_CAPABLE_VERSION_CODE = 2013
MAX_PATCH_RATIO = 0.85


def sha256_file(path: Path) -> str:
    digest = hashlib.sha256()
    with path.open("rb") as stream:
        for chunk in iter(lambda: stream.read(1024 * 1024), b""):
            digest.update(chunk)
    return digest.hexdigest()


def package_update(args: argparse.Namespace) -> dict:
    previous_apk = Path(args.from_apk).resolve()
    new_apk = Path(args.to_apk).resolve()
    media_dir = Path(args.media_dir).resolve()
    manifest_path = Path(args.manifest).resolve()
    if not previous_apk.is_file() or not new_apk.is_file():
        raise SystemExit("Both --from-apk and --to-apk must be existing APK files.")
    if args.to_code <= args.from_code:
        raise SystemExit("--to-code must be greater than --from-code.")

    media_dir.mkdir(parents=True, exist_ok=True)
    update_dir = media_dir / "updates"
    update_dir.mkdir(parents=True, exist_ok=True)
    published_apk = media_dir / "dubber-app.apk"
    if new_apk != published_apk:
        shutil.copy2(new_apk, published_apk)

    target_hash = sha256_file(published_apk)
    target_size = published_apk.stat().st_size
    patches: list[dict] = []
    patch_path = update_dir / f"dubber-app-{args.from_code}-to-{args.to_code}.patch"
    if patch_path.exists():
        patch_path.unlink()

    if args.from_code >= DELTA_CAPABLE_VERSION_CODE:
        with tempfile.TemporaryDirectory(prefix="dubber-patch-check-") as temp_dir:
            candidate = Path(temp_dir) / patch_path.name
            reconstructed = Path(temp_dir) / "reconstructed.apk"
            bsdiff4.file_diff(str(previous_apk), str(published_apk), str(candidate))
            patch_size = candidate.stat().st_size

            # Validate the generated artifact before making it available to
            # devices. A patch that is not meaningfully smaller is discarded.
            bsdiff4.file_patch(str(previous_apk), str(reconstructed), str(candidate))
            if sha256_file(reconstructed) != target_hash:
                raise RuntimeError("Generated patch failed its round-trip SHA-256 check.")
            if patch_size < int(target_size * MAX_PATCH_RATIO):
                shutil.move(str(candidate), patch_path)
                patches.append({
                    "from_version_code": args.from_code,
                    "base_apk_sha256": sha256_file(previous_apk),
                    "patch_url": f"/media/updates/{patch_path.name}",
                    "patch_sha256": sha256_file(patch_path),
                    "patch_size": patch_size,
                    "target_apk_sha256": target_hash,
                    "target_apk_size": target_size,
                })

    manifest = {
        "version_name": args.to_version_name,
        "version_code": args.to_code,
        "apk_url": "/media/dubber-app.apk",
        "apk_sha256": target_hash,
        "apk_size": target_size,
        "patches": patches,
        "changelog": args.changelog,
        "force_update": False,
    }
    manifest_path.parent.mkdir(parents=True, exist_ok=True)
    temporary_manifest = manifest_path.with_suffix(manifest_path.suffix + ".tmp")
    temporary_manifest.write_text(json.dumps(manifest, indent=2) + "\n", encoding="utf-8")
    os.replace(temporary_manifest, manifest_path)

    # Keep the newly published APK as the next release's local patch base.
    archive_dir = manifest_path.parent / "data" / "update_bases"
    archive_dir.mkdir(parents=True, exist_ok=True)
    shutil.copy2(published_apk, archive_dir / f"dubber-app-{args.to_code}.apk")
    return manifest


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--from-apk", required=True, help="Previous signed APK")
    parser.add_argument("--from-code", required=True, type=int, help="Previous versionCode")
    parser.add_argument("--to-apk", required=True, help="New signed APK")
    parser.add_argument("--to-code", required=True, type=int, help="New versionCode")
    parser.add_argument("--to-version-name", required=True)
    parser.add_argument("--media-dir", default="server/media")
    parser.add_argument("--manifest", default="server/app_update_manifest.json")
    parser.add_argument(
        "--changelog",
        default="App update",
        help="Short text displayed in Dubber's update prompt",
    )
    manifest = package_update(parser.parse_args())
    patch = manifest["patches"][0] if manifest["patches"] else None
    if patch:
        print(
            f"Packaged v{manifest['version_name']} ({manifest['version_code']}): "
            f"delta {patch['patch_size']:,} bytes, full APK {manifest['apk_size']:,} bytes"
        )
    else:
        print(
            f"Packaged v{manifest['version_name']} ({manifest['version_code']}) "
            f"as a full APK; no applicable/small delta is available."
        )
    print(f"Manifest: {Path('server/app_update_manifest.json')}")
    return 0


if __name__ == "__main__":
    sys.exit(main())
