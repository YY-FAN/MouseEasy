#!/usr/bin/env python3
"""Build the development app with Apple's Command Line Tools.

Swift sources are compiled locally. Only precompiled Interface Builder / asset
resources and Sparkle are obtained from the matching official MIT release.
Nothing is installed, launched, or granted permissions by this script.
"""

from __future__ import annotations

import argparse
import concurrent.futures
import hashlib
import json
import os
import plistlib
import shutil
import subprocess
import sys
import time
import tarfile
import tempfile

from PackageDMG import build_installer
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
WORK = ROOT / "build/local"
CACHE = WORK / "cache"
DEPS = CACHE / "dependencies"
MODULES = WORK / "modules"
VERSION = "0.13.0"
DISPLAY_NAME = "MouseEasy"
BUNDLE_ID = "io.github.yyfan.MouseWorkbench.dev"
EXECUTABLE = DISPLAY_NAME
APP = ROOT / "build" / f"{DISPLAY_NAME}.app"


def run(args: list[str | Path], **kwargs):
    return subprocess.run([str(x) for x in args], check=True, **kwargs)


def download(url: str, dest: Path):
    if dest.exists():
        return
    dest.parent.mkdir(parents=True, exist_ok=True)
    temporary = dest.with_name(dest.name + ".partial")
    run(["curl", "--fail", "--location", "--silent", "--show-error", "--retry", "2", url, "-o", temporary])
    temporary.replace(dest)


def prepare_cache():
    pins = json.loads((ROOT / "LinearMouse.xcodeproj/project.xcworkspace/xcshareddata/swiftpm/Package.resolved").read_text())["pins"]

    def fetch(pin):
        name = pin["identity"]
        if name == "jsonpatcher":
            return
        repo = pin["location"].removesuffix(".git").removeprefix("https://github.com/")
        archive = CACHE / "downloads" / (name + ".tar.gz")
        download(f"https://codeload.github.com/{repo}/tar.gz/{pin['state']['revision']}", archive)
        target = DEPS / name
        if not target.exists():
            target.mkdir(parents=True)
            with tarfile.open(archive) as tar:
                for member in tar.getmembers():
                    parts = Path(member.name).parts[1:]
                    if not parts:
                        continue
                    member.name = str(Path(*parts))
                    tar.extract(member, target, filter="data")

    with concurrent.futures.ThreadPoolExecutor(max_workers=4) as pool:
        list(pool.map(fetch, pins))

    sparkle_zip = CACHE / "downloads/Sparkle-for-Swift-Package-Manager.zip"
    download("https://github.com/lujjjh/Sparkle/releases/download/2.4.0/Sparkle-for-Swift-Package-Manager.zip", sparkle_zip)
    expected_sparkle = "6f58c030057c3eb38f7b422a06eb6df9212ef2dcc8686f2ec5fdb08d9647127d"
    if hashlib.sha256(sparkle_zip.read_bytes()).hexdigest() != expected_sparkle:
        raise RuntimeError("Sparkle archive differs from the pinned Swift package checksum")
    if not SPARKLE_FRAMEWORK.exists():
        # ditto preserves the framework's symlinks; zipfile.extractall does not.
        run(["ditto", "-xk", sparkle_zip, CACHE / "sparkle-sdk"])

    dmg = CACHE / "downloads" / f"LinearMouse-{VERSION}.dmg"
    download(f"https://github.com/linearmouse/linearmouse/releases/download/v{VERSION}/LinearMouse.dmg", dmg)
    if hashlib.sha256(dmg.read_bytes()).hexdigest() != "609276d5db79874034c9469a4eb56ccde6ed6fd01c52404f41fd4b493042789b":
        raise RuntimeError("LinearMouse resource archive differs from its official GitHub release digest")
    official = CACHE / "LinearMouse-official.app"
    if not official.exists():
        mount = WORK / "release-mount"
        mount.mkdir(parents=True, exist_ok=True)
        run(["hdiutil", "attach", "-nobrowse", "-readonly", dmg, "-mountpoint", mount])
        try:
            run(["ditto", mount / "LinearMouse.app", official])
        finally:
            run(["hdiutil", "detach", mount])
    return official


def sources(directory: Path):
    return sorted(directory.rglob("*.swift"))


def build_module(name: str, source_dir: Path, *, dependencies=(), swift_version="5", c_target=None, frameworks=()):
    output = MODULES / f"lib{name}.dylib"
    swift_sources = sources(source_dir)
    command = ["swiftc", "-swift-version", swift_version, "-sdk", SDK, "-target", TARGET,
               "-module-cache-path", WORK / "module-cache", "-emit-library", "-emit-module",
               "-module-name", name, "-emit-module-path", MODULES / f"{name}.swiftmodule",
               "-I", MODULES, "-L", MODULES, "-Xlinker", "-install_name", "-Xlinker", f"@rpath/lib{name}.dylib",
               "-file-prefix-map", f"{ROOT}=.", "-g", "-Onone"]
    extra_inputs = []
    if c_target:
        module_name, header, implementation = c_target
        module_dir = MODULES / module_name
        module_dir.mkdir(exist_ok=True)
        (module_dir / "module.modulemap").write_text(f'module {module_name} {{\n header "{header}"\n export *\n}}\n')
        command += ["-I", module_dir]
        extra_inputs += [header, implementation]
        if implementation:
            obj = module_dir / (module_name + ".o")
            run(["clang", "-isysroot", SDK, "-target", TARGET, "-fobjc-arc", "-c", implementation, "-o", obj])
            command += [obj]
    for dependency in dependencies:
        command += [f"-l{dependency}"]
        extra_inputs.append(MODULES / f"lib{dependency}.dylib")
    for framework in frameworks:
        command += ["-framework", framework]
    command += [path.relative_to(ROOT) for path in swift_sources] + ["-o", output]
    inputs = [x for x in swift_sources + extra_inputs if x]
    digest = hashlib.sha256((json.dumps([str(x) for x in command]) + TOOLCHAIN).encode())
    for p in inputs:
        digest.update(Path(p).read_bytes())
    stamp = output.with_suffix(".build-hash")
    if output.exists() and stamp.exists() and stamp.read_text() == digest.hexdigest():
        print(f"Cached {name}", flush=True)
        return output
    print(f"Compiling {name} ({len(swift_sources)} Swift files)", flush=True)
    run(command, cwd=ROOT)
    stamp.write_text(digest.hexdigest())
    return output


def compile_all(official):
    MODULES.mkdir(parents=True, exist_ok=True)
    libs = []
    for name, directory in [
        ("Defaults", "defaults/Sources/Defaults"),
        ("PublishedObject", "publishedobject/Sources/PublishedObject"),
        ("AppMover", "appmover/Sources/AppMover"),
        ("LaunchAtLogin", "launchatlogin/Sources/LaunchAtLogin"),
        ("LRUCache", "lrucache/Sources"),
        ("Version", "version/Sources/Version"),
    ]:
        libs.append(build_module(name, DEPS / directory))
    libs.append(build_module("ObservationToken", ROOT / "Modules/ObservationToken/Sources/ObservationToken"))
    libs.append(build_module("PointerKit", ROOT / "Modules/PointerKit/Sources/PointerKit",
                             dependencies=["ObservationToken"], frameworks=["IOKit"],
                             c_target=("PointerKitC", ROOT / "Modules/PointerKit/Sources/PointerKitC/include/IOKitSPIMac.h", None)))
    libs.append(build_module("KeyKit", ROOT / "Modules/KeyKit/Sources/KeyKit", frameworks=["IOKit", "Carbon"],
                             c_target=("KeyKitC", ROOT / "Modules/KeyKit/Sources/KeyKitC/include/KeyKitC.h", ROOT / "Modules/KeyKit/Sources/KeyKitC/KeyKitC.m")))
    libs.append(build_module("GestureKit", ROOT / "Modules/GestureKit/Sources/GestureKit", swift_version="6"))
    libs.append(build_module("DockKit", ROOT / "Modules/DockKit/Sources/DockKit", swift_version="6", frameworks=["ApplicationServices"],
                             c_target=("DockKitC", ROOT / "Modules/DockKit/Sources/DockKitC/include/ApplicationServicesSPI.h", None)))
    libs.append(build_module("HIDPP", ROOT / "Modules/HIDPP/Sources/HIDPP", swift_version="6"))

    process_obj = WORK / "Process.o"
    run(["clang", "-isysroot", SDK, "-target", TARGET, "-fobjc-arc", "-c", ROOT / "LinearMouse/Utilities/Process.m", "-o", process_obj])
    app_sources = sources(ROOT / "LinearMouse")
    executable = WORK / EXECUTABLE
    command = ["swiftc", "-swift-version", "5", "-sdk", SDK, "-target", TARGET,
               "-module-cache-path", WORK / "module-cache", "-module-name", "LinearMouse", "-parse-as-library",
               "-whole-module-optimization",
               "-D", "DEBUG", "-file-prefix-map", f"{ROOT}=.", "-g", "-Onone", "-I", MODULES, "-L", MODULES,
               "-import-objc-header", ROOT / "LinearMouse/LinearMouse-Bridging-Header.h",
               "-F", SPARKLE_FRAMEWORK.parent, "-framework", "Sparkle", "-framework", "IOKit",
               "-Xlinker", "-rpath", "-Xlinker", "@executable_path/../Frameworks"]
    for module_name in ["PointerKitC", "KeyKitC", "DockKitC"]:
        command += ["-I", MODULES / module_name]
    command += [f"-l{x.name.removeprefix('lib').removesuffix('.dylib')}" for x in libs]
    command += [path.relative_to(ROOT) for path in app_sources] + [process_obj, "-o", executable]
    print(f"Compiling application ({len(app_sources)} Swift files)", flush=True)
    (WORK / "swiftc-command.json").write_text(json.dumps([str(x) for x in command], ensure_ascii=False, indent=2))
    run(command, cwd=ROOT)
    return executable, libs


def package_localizations(resources):
    # Interface Builder resources come from the pinned release. Overlay this
    # checkout's strings without discarding its compiled plural forms.
    entries = json.loads((ROOT / "LinearMouse/Localizable.xcstrings").read_text())["strings"]
    for language in ("en", "zh-Hans"):
        folder = resources / f"{language}.lproj"
        strings_path = folder / "Localizable.strings"
        strings = plistlib.loads(subprocess.check_output(["plutil", "-convert", "binary1", "-o", "-", strings_path]))
        for key, entry in entries.items():
            unit = entry.get("localizations", {}).get(language, {}).get("stringUnit")
            if unit and "value" in unit:
                strings[key] = unit["value"]
        strings_path.write_bytes(plistlib.dumps(strings, fmt=plistlib.FMT_BINARY))
        menu = ROOT / "LinearMouse/UI" / folder.name / "Main.strings"
        if menu.is_file():
            shutil.copy2(menu, folder / "Main.strings")
        info_path = folder / "InfoPlist.strings"
        info = plistlib.loads(subprocess.check_output(["plutil", "-convert", "binary1", "-o", "-", info_path])) if info_path.exists() else {}
        source_info = ROOT / "LinearMouse" / folder.name / "InfoPlist.strings"
        if source_info.exists():
            info.update(plistlib.loads(subprocess.check_output(["plutil", "-convert", "binary1", "-o", "-", source_info])))
        info_path.write_bytes(plistlib.dumps(info, fmt=plistlib.FMT_BINARY))


def assemble(official, executable, libs, app, *, preview):
    display_name = f"{DISPLAY_NAME} Preview" if preview else DISPLAY_NAME
    bundle_id = BUNDLE_ID + ".preview" if preview else BUNDLE_ID
    contents = app / "Contents"
    (contents / "MacOS").mkdir(parents=True)
    run(["ditto", official / "Contents/Resources", contents / "Resources"])
    package_localizations(contents / "Resources")
    shutil.copy2(ROOT / "LinearMouse/ProjectLinks.plist", contents / "Resources")
    branding = ROOT / "Branding/Generated"
    for filename in ["WheelEase.icns", "WheelEaseMenuIcon.pdf"]:
        shutil.copy2(branding / filename, contents / "Resources" / filename)
    shutil.copy2(ROOT / "Documentation/Configuration.json", contents / "Resources/Configuration.json")
    # Official resource bundles contain localized app names. Override only the
    # product metadata, retaining translated permission notices and attribution.
    for localized_info in (contents / "Resources").glob("*.lproj/InfoPlist.strings"):
        metadata = plistlib.loads(subprocess.check_output([
            "plutil", "-convert", "binary1", "-o", "-", str(localized_info)
        ]))
        metadata["CFBundleName"] = display_name
        metadata["CFBundleDisplayName"] = display_name
        for key, value in metadata.items():
            if isinstance(value, str):
                metadata[key] = value.replace("LinearMouse", display_name)
        localized_info.write_bytes(plistlib.dumps(metadata, fmt=plistlib.FMT_BINARY))

    run(["ditto", SPARKLE_FRAMEWORK, contents / "Frameworks/Sparkle.framework"])
    helper = contents / "Library/LoginItems/LaunchAtLoginHelper.app"
    run(["ditto", official / "Contents/Library/LoginItems/LaunchAtLoginHelper.app", helper])
    helper_info_path = helper / "Contents/Info.plist"
    helper_info = plistlib.loads(helper_info_path.read_bytes())
    helper_info["CFBundleIdentifier"] = bundle_id + "-LaunchAtLoginHelper"
    helper_info_path.write_bytes(plistlib.dumps(helper_info))
    shutil.copy2(executable, contents / "MacOS" / EXECUTABLE)
    for lib in libs:
        shutil.copy2(lib, contents / "Frameworks" / lib.name)
    if not preview:
        # Leave debug symbols in the build directory. The app ships only the
        # runtime binaries, without the linker's local object-file paths.
        for binary in [contents / "MacOS" / EXECUTABLE, *(contents / "Frameworks" / lib.name for lib in libs)]:
            run(["strip", "-S", binary])

    info = plistlib.loads((ROOT / "LinearMouse/Info.plist").read_bytes())
    versions = dict(line.split(" = ", 1) for line in (ROOT / "Config.xcconfig").read_text().splitlines()
                    if line.startswith(("MARKETING_VERSION = ", "CURRENT_PROJECT_VERSION = ")))
    info.update({"CFBundleIdentifier": bundle_id, "CFBundleName": display_name, "CFBundleDisplayName": display_name,
                 "CFBundleExecutable": EXECUTABLE, "CFBundleShortVersionString": versions["MARKETING_VERSION"], "CFBundleVersion": versions["CURRENT_PROJECT_VERSION"],
                 "CFBundleDevelopmentRegion": "en", "CFBundlePackageType": "APPL", "CFBundleIconFile": "WheelEase",
                 "LSMinimumSystemVersion": "12.0", "NSHumanReadableCopyright": "Based on LinearMouse. MIT License. Local development version.",
                 "SUEnableAutomaticChecks": False, "SUAllowsAutomaticUpdates": False})
    if preview:
        info["MouseEasySettingsPreview"] = True
    info.pop("SUFeedURL", None)
    info.pop("CFBundleIconName", None)
    info.pop("CFBundleIcons", None)
    (contents / "Info.plist").write_bytes(plistlib.dumps(info))
    (contents / "PkgInfo").write_bytes(b"APPL????")
    notices = contents / "Resources/ThirdPartyLicenses"
    notices.mkdir()
    shutil.copy2(ROOT / "LICENSE", notices / "LinearMouse-LICENSE.txt")
    pins = json.loads((ROOT / "LinearMouse.xcodeproj/project.xcworkspace/xcshareddata/swiftpm/Package.resolved").read_text())["pins"]
    license_manifest = [{
        "component": "LinearMouse and local Modules",
        "source": f"https://github.com/linearmouse/linearmouse/tree/v{VERSION}",
        "licenseFile": "LinearMouse-LICENSE.txt",
        "licenseSHA256": hashlib.sha256((ROOT / "LICENSE").read_bytes()).hexdigest(),
    }]
    used_dependencies = {lib.name.removeprefix("lib").removesuffix(".dylib").lower() for lib in libs}
    used_dependencies.add("sparkle")
    for dep in DEPS.iterdir():
        if dep.name not in used_dependencies:
            continue
        for filename in ["LICENSE", "LICENSE.md", "LICENSE.txt", "README.md"]:
            license_path = dep / filename
            if license_path.exists():
                license_text = license_path.read_text()
                if filename == "README.md":
                    if "## License" not in license_text:
                        continue
                    license_text = license_text[license_text.index("## License"):]
                (notices / f"{dep.name}-LICENSE.txt").write_text(license_text)
                pin = next(x for x in pins if x["identity"] == dep.name)
                license_manifest.append({
                    "component": dep.name, "source": pin["location"], "revision": pin["state"]["revision"],
                    "licenseFile": f"{dep.name}-LICENSE.txt",
                    "licenseSHA256": hashlib.sha256(license_text.encode()).hexdigest(),
                })
                break
    for p in (ROOT / "Modules").rglob("*.h"):
        if p.name in ["IOKitSPIMac.h", "CGSInternal.h", "ApplicationServicesSPI.h"]:
            shutil.copy2(p, notices / f"{p.parent.name}-{p.name}.txt")
    shutil.copy2(ROOT / "Modules/ObservationToken/Sources/ObservationToken/LifetimeAssociation.swift",
                 notices / "ObservationToken-SindreSorhus-MIT.txt")
    manifest_json = json.dumps({"dependencies": license_manifest,
                               "excludedUpstreamDependencies": [{"component": "JSONPatcher", "reason": "Pinned upstream package has no declared license; replaced by independently implemented JSONCommentSanitizer."}],
                               "supplementalNotices": [p.name for p in notices.iterdir() if p.name.endswith('.h.txt') or 'SindreSorhus' in p.name]},
                              ensure_ascii=False, indent=2) + "\n"
    (notices / "manifest.json").write_text(manifest_json)
    (WORK / "dependency-license-manifest.json").write_text(manifest_json)
    (contents / "Resources/BuildProvenance.json").write_text(json.dumps({
        "base": "https://github.com/linearmouse/linearmouse/tree/v0.13.0",
        "resourceRelease": f"https://github.com/linearmouse/linearmouse/releases/tag/v{VERSION}",
        "resourceArchiveSHA256": hashlib.sha256((CACHE / "downloads" / f"LinearMouse-{VERSION}.dmg").read_bytes()).hexdigest(),
        "sparkleArchiveSHA256": hashlib.sha256((CACHE / "downloads/Sparkle-for-Swift-Package-Manager.zip").read_bytes()).hexdigest(),
        "sdk": SDK, "compiler": TOOLCHAIN, "target": TARGET,
    }, ensure_ascii=False, indent=2) + "\n")
    run(["codesign", "--force", "--deep", "--sign", "-", app])
    run(["codesign", "--verify", "--deep", "--strict", app])
    report = {"app": str(app), "bundleID": bundle_id, "displayName": display_name,
              "version": info["CFBundleShortVersionString"], "target": TARGET, "sdk": SDK,
              "executableSHA256": hashlib.sha256((contents / "MacOS" / EXECUTABLE).read_bytes()).hexdigest(),
              "configurationSchemaSHA256": hashlib.sha256((contents / "Resources/Configuration.json").read_bytes()).hexdigest(),
              "upstreamUpdateFeedPresent": "SUFeedURL" in info, "deepCodeSignatureVerified": True,
              "runtimeStarted": False}
    return report


def package(official, executable, libs, *, preview=False):
    display_name = f"{DISPLAY_NAME} Preview" if preview else DISPLAY_NAME
    output = APP.with_name(f"{display_name}.app")
    old_product = WORK / "products.noindex" / output.name
    if output.is_symlink() and output.resolve() != old_product:
        raise RuntimeError(f"Unexpected application link: {output}")

    def archive_product(path):
        if path.exists():
            archives = WORK / "archives.noindex"
            archives.mkdir(exist_ok=True)
            path.rename(archives / f"{display_name}-{time.time_ns()}.app.saved")

    if preview:
        if not output.is_symlink():
            archive_product(output)
        archive_product(old_product)
        report = assemble(official, executable, libs, old_product, preview=True)
        if not output.is_symlink():
            output.symlink_to(old_product.relative_to(output.parent), target_is_directory=True)
    else:
        # A mounted image or a build folder must never offer another launchable
        # copy of the installed release identity.
        with tempfile.TemporaryDirectory(suffix=".noindex") as staging:
            app = Path(staging) / "payload" / output.name
            report = assemble(official, executable, libs, app, preview=False)
            installer = APP.with_suffix(".pkg")
            build_installer(app, installer)
        if output.is_symlink():
            output.unlink()
        else:
            archive_product(output)
        archive_product(old_product)
        report.pop("app")
        report["installer"] = str(installer)
        output = installer
    (WORK / ("preview-report.json" if preview else "build-report.json")).write_text(
        json.dumps(report, ensure_ascii=False, indent=2) + "\n")
    print(output, flush=True)


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--prepare-only", action="store_true")
    parser.add_argument("--preview", action="store_true", help="Build an isolated settings-only preview app")
    args = parser.parse_args()
    WORK.mkdir(parents=True, exist_ok=True)
    official = prepare_cache()
    if args.prepare_only:
        return
    executable, libs = compile_all(official)
    package(official, executable, libs, preview=args.preview)


SDK = os.environ.get("MOUSEWORKBENCH_SDK")
if not SDK:
    # CLT 27 omits the SwiftUIMacros plugin required by its new @State macro.
    # Building against the installed 26 SDK uses the supported property wrapper
    # ABI and the resulting application runs on macOS 27 normally.
    sdk26 = Path("/Library/Developer/CommandLineTools/SDKs/MacOSX26.sdk")
    SDK = str(sdk26.resolve()) if sdk26.exists() else subprocess.check_output(["xcrun", "--sdk", "macosx", "--show-sdk-path"], text=True).strip()
TOOLCHAIN = subprocess.check_output(["swiftc", "--version"], text=True).strip()
TARGET = "arm64-apple-macosx12.0"
SPARKLE_FRAMEWORK = CACHE / "sparkle-sdk/Sparkle.xcframework/macos-arm64_x86_64/Sparkle.framework"

if __name__ == "__main__":
    try:
        main()
    except subprocess.CalledProcessError as error:
        print(f"Build stopped: {Path(error.cmd[0]).name} exited with {error.returncode}.", file=sys.stderr)
        raise SystemExit(error.returncode)
