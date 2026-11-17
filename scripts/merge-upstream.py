#!/usr/bin/env python3
"""Merge upstream into a clean sync branch, retaining jm release numbers."""
import re
import subprocess
import sys
from pathlib import Path


def git(*args, check=True):
    return subprocess.run(["git", *args], check=check, text=True,
                          encoding="utf-8", stdout=subprocess.PIPE,
                          stderr=subprocess.PIPE)


def version(text, path):
    pattern = r'^SCRIPT_VERSION="([^"]+)"$' if path == "remnanode.sh" else r"^# Version: (\S+)$"
    match = re.search(pattern, text, re.M)
    if not match:
        raise ValueError(f"Missing version in {path}")
    return match.group(1)


def main():
    if len(sys.argv) != 2:
        raise ValueError("Usage: merge-upstream.py <upstream-ref>")
    if git("status", "--porcelain").stdout.strip():
        raise ValueError("Use a clean, separate sync branch")
    upstream = git("rev-parse", "--verify", "--end-of-options", sys.argv[1] + "^{commit}").stdout.strip()
    if git("merge-base", "--is-ancestor", upstream, "HEAD", check=False).returncode == 0:
        print("Upstream is already included")
        return

    releases = {}
    for path in ("remnanode.sh", "remnanode-xray-update.sh"):
        current = version(Path(path).read_text(encoding="utf-8"), path)
        original = version(git("show", f"{upstream}:{path}").stdout, path)
        fork = re.fullmatch(r"(\d+\.\d+\.\d+)-jm\.(\d+)", current)
        if not fork or not re.fullmatch(r"\d+\.\d+\.\d+", original):
            raise ValueError(f"Review the changed version format in {path}")
        if tuple(map(int, original.split('.'))) < tuple(map(int, fork[1].split('.'))):
            raise ValueError(f"Refusing an upstream downgrade in {path}")
        revision = int(fork[2]) + 1 if original == fork[1] else 1
        releases[path] = current, f"{original}-jm.{revision}"

    merged = git("-c", "merge.conflictStyle=merge", "merge", "--no-ff", "--no-commit", upstream, check=False)
    conflicts = git("diff", "--name-only", "--diff-filter=U").stdout.splitlines()
    if merged.returncode and not conflicts:
        raise ValueError(merged.stderr)
    # Resolve only version lines. Changes to executable code always need review.
    for path in conflicts:
        if path not in releases:
            continue
        text = Path(path).read_text(encoding="utf-8")

        def resolve(match):
            ours, theirs = match[1], match[2]
            metadata = r'^(?:# Version: \S+|SCRIPT_VERSION="[^"]+")\n'
            if re.sub(metadata, "", ours, flags=re.M) == re.sub(metadata, "", theirs, flags=re.M):
                return ours
            return match[0]

        text = re.sub(r"^<<<<<<< [^\n]+\n(.*?)^=======\n(.*?)^>>>>>>> [^\n]+\n", resolve, text, flags=re.M | re.S)
        if not re.search(r"^(?:<<<<<<< |=======|>>>>>>> )", text, re.M):
            Path(path).write_text(text, encoding="utf-8", newline="\n")
            git("add", "--", path)
    unresolved = git("diff", "--name-only", "--diff-filter=U").stdout.strip()
    if unresolved:
        raise ValueError("Resolve these conflicts before publishing; our features were not discarded:\n" + unresolved)

    for path, (old, new) in releases.items():
        text = Path(path).read_text(encoding="utf-8")
        text = re.sub(r"^# Version: \S+$", f"# Version: {new}", text, flags=re.M)
        if path == "remnanode.sh":
            text = re.sub(r'^SCRIPT_VERSION="[^"]+"$', f'SCRIPT_VERSION="{new}"', text, flags=re.M)
        Path(path).write_text(text, encoding="utf-8", newline="\n")
        git("add", "--", path)
    old, new = releases["remnanode.sh"]
    for path in ("README.md", "README_RU.md"):
        if Path(path).exists():
            Path(path).write_text(Path(path).read_text(encoding="utf-8").replace(old, new), encoding="utf-8", newline="\n")
            git("add", "--", path)
    git("commit", "-m", f"Merge upstream {upstream[:12]}; release v{new}")
    print(f"Prepared v{new}; run tests before publishing")


if __name__ == "__main__":
    try:
        main()
    except (ValueError, subprocess.CalledProcessError) as error:
        sys.exit(str(error))
