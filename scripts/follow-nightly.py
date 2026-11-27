#!/usr/bin/env python3
"""Follow the latest Aura nightly into an orchestra repo (#5486).

Run from any member/stage repo:
  python3 follow-nightly.py --repo .

The updater reads the nightly manifest, pins the immutable per-build assets
(never the rolling alias), patches aura.toml / AURA_REF when present, and
updates the third_party/aura gitlink in a submodule repo. It prints nothing
and changes nothing when the repo is already on the manifest's build.
"""

from __future__ import annotations

import argparse
import json
import pathlib
import re
import runpy
import subprocess
import sys

HERE = pathlib.Path(__file__).resolve().parent
_BUMP = runpy.run_path(str(HERE / "bump-baseline.py"))
fetch_upstream = _BUMP["fetch_upstream"]
make_baseline = _BUMP["make_baseline"]
dependency_block = _BUMP["dependency_block"]


def patch_toml(path: pathlib.Path, deps: dict[str, str]) -> None:
    text = path.read_text()
    for key, value in deps.items():
        pattern = rf'(?m)^{re.escape(key)}\s*=\s*"[^"]*"'
        if not re.search(pattern, text):
            raise SystemExit(f"{path}: missing dependencies.{key}")
        text = re.sub(pattern, f'{key} = "{value}"', text, count=1)
    path.write_text(text)


def patch_workflows(repo: pathlib.Path, digest: str) -> None:
    pattern = re.compile(r"ghcr\.io/cybrid-systems/aura-ci@sha256:[0-9a-f]{64}")
    replacement = f"ghcr.io/cybrid-systems/aura-ci@{digest}"
    for path in sorted((repo / ".github" / "workflows").glob("*.y*ml")):
        text = path.read_text()
        updated = pattern.sub(replacement, text)
        if updated != text:
            path.write_text(updated)
            print(f"patched {path.relative_to(repo)}")


def main() -> int:
    ap = argparse.ArgumentParser(description=__doc__)
    ap.add_argument("--repo", type=pathlib.Path, default=pathlib.Path.cwd())
    args = ap.parse_args()
    repo = args.repo.resolve()
    baseline_path = repo / "baseline" / "aura-baseline.json"
    current = json.loads(baseline_path.read_text())
    upstream = fetch_upstream()
    next_base = make_baseline(current, upstream)

    same = (
        current["aura"]["commit_sha"] == next_base["aura"]["commit_sha"]
        and current["aura"]["assets"] == next_base["aura"]["assets"]
        and current["aura_ci"]["digest"] == next_base["aura_ci"]["digest"]
    )
    if same:
        print(f"baseline up to date: {next_base['aura']['commit_sha'][:9]}")
        return 0

    baseline_path.write_text(json.dumps(next_base, indent=2, sort_keys=True) + "\n")
    print(f"baseline -> {next_base['aura']['commit_sha'][:9]}")

    toml = repo / "aura.toml"
    if toml.is_file():
        patch_toml(toml, dependency_block(next_base))
        print("patched aura.toml")

    patch_workflows(repo, next_base["aura_ci"]["digest"])

    ref = repo / "AURA_REF"
    if ref.is_file():
        ref.write_text(next_base["aura"]["commit_sha"] + "\n")
        print("patched AURA_REF")

    gitmodules = repo / ".gitmodules"
    if gitmodules.is_file() and "third_party/aura" in gitmodules.read_text():
        subprocess.run(
            [
                "git",
                "update-index",
                "--cacheinfo",
                f"160000,{next_base['aura']['commit_sha']},third_party/aura",
            ],
            cwd=repo,
            check=True,
        )
        subprocess.run(
            ["git", "submodule", "update", "--init", "--", "third_party/aura"],
            cwd=repo,
            check=True,
        )
        print("pinned third_party/aura gitlink")

    return 0


if __name__ == "__main__":
    raise SystemExit(main())
