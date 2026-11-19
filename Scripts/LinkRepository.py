#!/usr/bin/env python3
"""Associate MouseEasy with an existing GitHub repository without pushing."""
import argparse
import os
from pathlib import Path
import plistlib
import re
import subprocess
import tempfile


def link(root, slug):
    if not re.fullmatch(r"[A-Za-z0-9-]+/[A-Za-z0-9_.-]+", slug) or slug.split("/")[1] in (".", ".."):
        raise ValueError("Supply the GitHub repository as OWNER/REPOSITORY.")
    if slug.lower() == "linearmouse/linearmouse" or slug.endswith(".git"):
        raise ValueError("Use the MouseEasy owner's repository name, without .git.")
    url = "https://github.com/" + slug
    resource = root / "LinearMouse/ProjectLinks.plist"
    config = plistlib.loads(resource.read_bytes())
    if config.get("repository") and config["repository"].lower() != url.lower():
        raise ValueError("ProjectLinks.plist already identifies a different repository.")

    def git(*args):
        return subprocess.check_output(["git", *args], cwd=root, text=True).strip()

    add_origin = "origin" not in git("remote").splitlines()
    if not add_origin:
        valid = {url.lower(), "git@github.com:" + slug.lower(), "ssh://git@github.com/" + slug.lower()}
        for args in (("get-url", "--all"), ("get-url", "--push", "--all")):
            addresses = git("remote", *args, "origin").splitlines()
            if not addresses or any(address.removesuffix(".git").lower() not in valid for address in addresses):
                raise ValueError("The existing origin points elsewhere. No links were changed.")
    config["repository"] = url
    with tempfile.NamedTemporaryFile(dir=resource.parent, delete=False) as out:
        pending = Path(out.name)
        try:
            out.write(plistlib.dumps(config, sort_keys=False))
            out.flush()
            os.chmod(pending, resource.stat().st_mode & 0o777)
            if add_origin:
                git("remote", "add", "origin", url + ".git")
            os.replace(pending, resource)
        finally:
            pending.unlink(missing_ok=True)
    print("Local origin and application link:", url)


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("repository", metavar="OWNER/REPOSITORY")
    try:
        link(Path(__file__).resolve().parent.parent, parser.parse_args().repository)
    except (ValueError, OSError, subprocess.CalledProcessError) as error:
        parser.exit(1, str(error) + "\n")
