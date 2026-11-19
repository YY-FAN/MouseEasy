#!/usr/bin/env python3
"""Package the local MouseEasy build and its bilingual download page."""
import hashlib
import argparse
import os
import plistlib
from pathlib import Path
import re
import subprocess
import tempfile

ROOT = Path(__file__).resolve().parent.parent
BUILD = ROOT / "build"
APP = BUILD / "MouseEasy.app"


def run(*args):
    subprocess.run(args, check=True)


def digest(path):
    return hashlib.sha256(path.read_bytes()).hexdigest()


def main(output_dir):
    metadata = Path("Contents/Info.plist")
    info = plistlib.loads((APP / metadata).read_bytes())
    version = info["CFBundleShortVersionString"]
    if not re.fullmatch(r"[0-9]+(?:\.[0-9]+){1,3}", version) or info.get("MouseEasySettingsPreview"):
        raise ValueError("Expected a versioned MouseEasy build")
    name = f"MouseEasy-{version}.dmg"
    binary = Path("Contents/MacOS") / info["CFBundleExecutable"]
    run("codesign", "--verify", "--deep", "--strict", APP)
    output_dir.mkdir(parents=True, exist_ok=True)
    with tempfile.TemporaryDirectory(dir=output_dir, suffix=".noindex") as staging:
        directory = Path(staging)
        source = directory / "source"
        source.mkdir()
        run("ditto", APP.resolve(), source / APP.name)
        (source / "Applications").symlink_to("/Applications")
        image = directory / name
        run("hdiutil", "create", "-volname", f"MouseEasy {version}", "-srcfolder", source, "-format", "UDZO", image)
        run("hdiutil", "verify", image)
        mount = directory / "mounted"
        mount.mkdir()
        run("hdiutil", "attach", "-readonly", "-nobrowse", "-mountpoint", mount, image)
        try:
            restored = mount / APP.name
            run("codesign", "--verify", "--deep", "--strict", restored)
            if (restored / metadata).read_bytes() != (APP / metadata).read_bytes() or digest(restored / binary) != digest(APP / binary):
                raise ValueError("The packaged app differs from the local build")
            if os.readlink(mount / "Applications") != "/Applications":
                raise ValueError("Missing Applications shortcut")
        finally:
            run("hdiutil", "detach", mount)
        page = (ROOT / "docs/download.html").read_text()
        for lang, label in (("zh", "下载安装包"), ("en", "Download installer")):
            page = page.replace(f"<!-- download-{lang} -->",
                                f'<p><a class="download" href="{name}" download>{label} · {version}</a></p>')
        (directory / "download.html").write_text(page)
        os.replace(image, output_dir / name)
        os.replace(directory / "download.html", output_dir / "download.html")
    print(f"{output_dir / name}\nSHA-256: {digest(output_dir / name)}\n{output_dir / 'download.html'}")


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--output-dir", type=Path, default=BUILD)
    main(parser.parse_args().output_dir.resolve())
