#!/usr/bin/env python3
"""Produce the fixed-location MouseEasy installer and verify the downloadable image."""
import argparse
import hashlib
import os
from pathlib import Path
import plistlib
import re
import shutil
import subprocess
import tempfile
from xml.etree import ElementTree

ROOT = Path(__file__).resolve().parent.parent
BUILD = ROOT / "build"
IDENTIFIER = "io.github.yyfan.MouseWorkbench.dev"
INSTALLER_ID = IDENTIFIER + ".installer"


def run(*args):
    subprocess.run(args, check=True)


def digest(path):
    return hashlib.sha256(path.read_bytes()).hexdigest()


def release_info(app):
    info = plistlib.loads((app / "Contents/Info.plist").read_bytes())
    if (app.name != "MouseEasy.app" or info.get("CFBundleIdentifier") != IDENTIFIER
            or info.get("CFBundlePackageType") != "APPL" or info.get("MouseEasySettingsPreview")
            or info.get("LSUIElement") or info.get("LSBackgroundOnly")
            or not re.fullmatch(r"[0-9]+(?:\.[0-9]+){1,3}", info["CFBundleShortVersionString"])
            or not info["CFBundleVersion"].isdigit()):
        raise ValueError("Expected a launcher-visible MouseEasy release")
    icon = Path(info["CFBundleIconFile"]).with_suffix(".icns")
    if not (app / "Contents/Resources" / icon).is_file():
        raise ValueError("Missing application icon")
    run("codesign", "--verify", "--deep", "--strict", app)
    return info


def inspect_installer(package):
    with tempfile.TemporaryDirectory(suffix=".noindex") as tmp:
        return inspect_payload(package, Path(tmp) / "expanded")


def inspect_payload(package, expanded):
    run("pkgutil", "--expand-full", package, expanded)
    metadata = ElementTree.parse(expanded / "PackageInfo").getroot()
    payload = expanded / "Payload"
    if (metadata.get("identifier") != INSTALLER_ID or metadata.get("install-location") != "/Applications"
            or metadata.findall("./relocate/*") or {p.name for p in payload.iterdir()} != {"MouseEasy.app"}
            or metadata.find("./scripts/postinstall") is None):
        raise ValueError("Expected a nonrelocatable, single-app installer for /Applications")
    info = release_info(payload / "MouseEasy.app")
    if metadata.get("version") != info["CFBundleShortVersionString"] + "." + info["CFBundleVersion"]:
        raise ValueError("Installer and payload versions differ")
    return info


def build_installer(app, destination):
    info = release_info(app)
    version = info["CFBundleShortVersionString"] + "." + info["CFBundleVersion"]
    with tempfile.TemporaryDirectory(dir=destination.parent, suffix=".noindex") as tmp:
        tmp = Path(tmp)
        component = tmp / "component.plist"
        component.write_bytes(plistlib.dumps([{
            "RootRelativeBundlePath": app.name, "BundleIsRelocatable": False,
            "BundleIsVersionChecked": True, "BundleHasStrictIdentifier": True, "BundleOverwriteAction": "upgrade",
        }]))
        package = tmp / "MouseEasy.pkg"
        run("/usr/bin/pkgbuild", "--root", app.parent, "--install-location", "/Applications",
            "--component-plist", component, "--identifier", INSTALLER_ID, "--version", version,
            "--ownership", "recommended", "--scripts", ROOT / "Scripts/installer", package)
        inspect_installer(package)
        os.replace(package, destination)


def main(output_dir):
    package = BUILD / "MouseEasy.pkg"
    output_dir.mkdir(parents=True, exist_ok=True)
    with tempfile.TemporaryDirectory(dir=output_dir, suffix=".noindex") as staging:
        directory = Path(staging)
        source = directory / "source"
        source.mkdir()
        staged = source / package.name
        shutil.copyfile(package, staged)
        info = inspect_installer(staged)
        version = info["CFBundleShortVersionString"]
        name = f"MouseEasy-{version}-build{info['CFBundleVersion']}.dmg"
        image = directory / name
        run("hdiutil", "create", "-volname", f"MouseEasy {version}", "-srcfolder", source, "-format", "UDZO", image)
        run("hdiutil", "verify", image)
        mount = directory / "mounted"
        mount.mkdir()
        run("hdiutil", "attach", "-readonly", "-nobrowse", "-mountpoint", mount, image)
        try:
            if ({p.name for p in mount.iterdir() if not p.name.startswith(".")} != {package.name}
                    or digest(mount / package.name) != digest(staged)):
                raise ValueError("Unexpected installer or launchable copy on the disk image")
        finally:
            run("hdiutil", "detach", mount)
        page = (ROOT / "docs/download.html").read_text()
        for lang, label in (("zh", "下载安装包"), ("en", "Download installer")):
            page = page.replace(f"<!-- download-{lang} -->",
                                f'<p><a class="download" href="{name}" download>{label} · {version}</a></p>')
        (directory / "download.html").write_text(page)
        os.replace(image, output_dir / name)
        os.replace(directory / "download.html", output_dir / "download.html")
    print(f"{output_dir / name}\nSHA-256: {digest(output_dir / name)}")


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--output-dir", type=Path, default=BUILD)
    main(parser.parse_args().output_dir.resolve())
