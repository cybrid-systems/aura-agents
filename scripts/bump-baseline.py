#!/usr/bin/env python3
"""Orchestra baseline bump generator (#13).

Reads the locked aura commit / nightly archive digests / aura-ci digest,
compares them with the upstream rolling release, and emits a reviewed
baseline update plus standard Bump PR payloads for members and stages.

This script never writes a tag or a GitHub release. It only reads the
nightly release and the container manifest; --write updates the local
baseline file and prints the target payloads for a later reviewed PR.
"""

from __future__ import annotations

import argparse
import json
import pathlib
import re
import sys
import urllib.error
import urllib.request

ROOT = pathlib.Path(__file__).resolve().parent.parent
BASELINE = ROOT / "baseline" / "aura-baseline.json"
AURA_REPO = "cybrid-systems/aura"
AURA_CI_IMAGE = "ghcr.io/cybrid-systems/aura-ci"
HEX40 = re.compile(r"^[0-9a-f]{40}$")
SHA256 = re.compile(r"^[0-9a-f]{64}$")


def load(path: pathlib.Path) -> dict:
    with path.open("rb") as fh:
        return json.load(fh)


def validate(data: dict) -> None:
    aura = data["aura"]
    ci = data["aura_ci"]
    if not HEX40.fullmatch(aura["commit_sha"]):
        raise ValueError("aura.commit_sha is not a 40-char sha")
    for arch in ("linux-x86_64", "linux-arm64"):
        if not SHA256.fullmatch(aura["assets"][arch]["sha256"]):
            raise ValueError(f"aura.assets.{arch}.sha256 is malformed")
    if not ci["digest"].startswith("sha256:"):
        raise ValueError("aura_ci.digest is not sha256")


def gh_json(url: str) -> dict:
    req = urllib.request.Request(
        url,
        headers={
            "Accept": "application/vnd.github+json",
            "User-Agent": "aura-agents-baseline",
        },
    )
    token = __import__("os").environ.get("GITHUB_TOKEN") or __import__(
        "os"
    ).environ.get("GH_TOKEN")
    if token:
        req.add_header("Authorization", f"Bearer {token}")
    with urllib.request.urlopen(req, timeout=20) as resp:
        return json.load(resp)


def ghcr_digest(image: str = AURA_CI_IMAGE) -> str:
    token_url = f"https://ghcr.io/token?scope=repository:{image.split('/', 1)[1]}:pull&service=ghcr.io"
    with urllib.request.urlopen(token_url, timeout=20) as resp:
        token = json.load(resp)["token"]
    req = urllib.request.Request(
        f"https://ghcr.io/v2/{image.split('/', 1)[1]}/manifests/latest",
        headers={
            "Authorization": f"Bearer {token}",
            "Accept": "application/vnd.oci.image.index.v1+json,"
            "application/vnd.docker.distribution.manifest.list.v2+json,"
            "application/vnd.docker.distribution.manifest.v2+json",
        },
    )
    with urllib.request.urlopen(req, timeout=20) as resp:
        digest = resp.headers.get("Docker-Content-Digest")
    if not digest:
        raise ValueError("registry returned no Docker-Content-Digest")
    return digest


def fetch_upstream() -> dict:
    release = gh_json(f"https://api.github.com/repos/{AURA_REPO}/releases/tags/nightly")
    m = re.search(r"aura nightly @ ([0-9a-f]{7,40})", release.get("body", ""))
    if not m:
        raise ValueError("nightly release body has no commit sha")
    short = m.group(1)
    full = gh_json(f"https://api.github.com/repos/{AURA_REPO}/commits/{short}")["sha"]
    assets = {}
    for arch, name in (
        ("linux-x86_64", "aura-nightly-linux-x86_64.tar.gz"),
        ("linux-arm64", "aura-nightly-linux-arm64.tar.gz"),
    ):
        found = next(
            (a for a in release.get("assets", []) if a.get("name") == name), None
        )
        if not found or not found.get("digest", "").startswith("sha256:"):
            raise ValueError(f"nightly asset missing digest: {name}")
        assets[arch] = {"name": name, "sha256": found["digest"].removeprefix("sha256:")}
    return {
        "commit_sha": full,
        "nightly_updated_at": release.get("updated_at", ""),
        "assets": assets,
        "aura_ci_digest": ghcr_digest(),
    }


def make_baseline(current: dict, upstream: dict) -> dict:
    data = json.loads(json.dumps(current))
    data["generated_at"] = upstream.get("nightly_updated_at") or data.get(
        "generated_at", ""
    )
    data["aura"]["commit_sha"] = upstream["commit_sha"]
    data["aura"]["nightly_updated_at"] = upstream.get("nightly_updated_at", "")
    data["aura"]["assets"] = upstream["assets"]
    data["aura_ci"]["digest"] = upstream["aura_ci_digest"]
    validate(data)
    return data


def toml_for(baseline: dict) -> str:
    aura = baseline["aura"]
    ci = baseline["aura_ci"]
    return f'''name = "orchestra-target"
entry = "main.aura"
preset = "dev"
out = "out"

[dependencies]
aura = "nightly"
aura_commit = "{aura["commit_sha"]}"
aura_sha256_linux_x86_64 = "{aura["assets"]["linux-x86_64"]["sha256"]}"
aura_sha256_linux_arm64 = "{aura["assets"]["linux-arm64"]["sha256"]}"
aura_ci_digest = "{ci["digest"]}"
'''


def target_payloads(baseline: dict) -> list[dict]:
    payloads = []
    for repo in baseline.get("members", []) + baseline.get("stages", []):
        name = repo.split("/", 1)[1]
        payloads.append(
            {
                "repo": repo,
                "branch": f"orchestra/baseline-{baseline['aura']['commit_sha'][:9]}",
                "title": f"Bump orchestra Aura baseline to {baseline['aura']['commit_sha'][:9]}",
                "body": (
                    "Unattended orchestra baseline bump.\n\n"
                    f"- aura: {baseline['aura']['commit_sha']}\n"
                    f"- aura-ci: {baseline['aura_ci']['digest']}\n"
                    "- generated by scripts/bump-baseline.py; no tag or release write.\n"
                ),
                "files": {
                    "aura.toml": toml_for(baseline),
                    "baseline/aura-baseline.json": json.dumps(
                        baseline, indent=2, sort_keys=True
                    )
                    + "\n",
                },
                "workflow_patch": (
                    f"container.image: {AURA_CI_IMAGE}@{baseline['aura_ci']['digest']}"
                ),
                "rollback": {
                    "file": "baseline/aura-baseline.json",
                    "to": "the previous commit's baseline",
                },
                "forbidden_actions": ["force-push", "admin-merge", "tag", "release"],
                "target": name,
            }
        )
    return payloads


def simulate(
    current: dict, sha: str, digest: str, x86: str | None, arm: str | None
) -> dict:
    if not HEX40.fullmatch(sha):
        raise ValueError("--sha must be a 40-char lowercase hex")

    if not digest.startswith("sha256:"):
        raise ValueError("--ci-digest must start with sha256:")
    upstream = {
        "commit_sha": sha,
        "nightly_updated_at": "simulated",
        "assets": {
            "linux-x86_64": {
                "name": "aura-nightly-linux-x86_64.tar.gz",
                "sha256": x86 or current["aura"]["assets"]["linux-x86_64"]["sha256"],
            },
            "linux-arm64": {
                "name": "aura-nightly-linux-arm64.tar.gz",
                "sha256": arm or current["aura"]["assets"]["linux-arm64"]["sha256"],
            },
        },
        "aura_ci_digest": digest,
    }
    return make_baseline(current, upstream)


def self_test(current: dict) -> None:
    new_sha = "1" * 40
    new_digest = "sha256:" + "2" * 64
    next_base = simulate(current, new_sha, new_digest, "3" * 64, "4" * 64)
    assert next_base["aura"]["commit_sha"] == new_sha
    assert next_base["aura_ci"]["digest"] == new_digest
    payloads = target_payloads(next_base)
    assert len(payloads) == len(current.get("members", [])) + len(
        current.get("stages", [])
    )
    for p in payloads:
        assert p["repo"].startswith("cybrid-systems/")
        assert p["files"]["aura.toml"].count("aura_commit") == 1
        assert p["workflow_patch"].startswith("container.image: ghcr.io/")
        assert p["rollback"]["file"]
        assert "tag" in p["forbidden_actions"] and "release" in p["forbidden_actions"]
    old_payloads = target_payloads(current)
    assert old_payloads[0]["files"]["aura.toml"] != payloads[0]["files"]["aura.toml"]
    print("baseline-self-test=ok")
    print(f"payloads={len(payloads)}")


def main() -> int:
    ap = argparse.ArgumentParser(description=__doc__)
    ap.add_argument("--baseline", type=pathlib.Path, default=BASELINE)
    ap.add_argument(
        "--check", action="store_true", help="compare with upstream nightly"
    )
    ap.add_argument("--write", action="store_true", help="update the local baseline")
    ap.add_argument(
        "--simulate",
        action="store_true",
        help="build a baseline from --sha/--ci-digest",
    )
    ap.add_argument("--self-test", action="store_true")
    ap.add_argument("--sha", default="")
    ap.add_argument("--ci-digest", default="")
    ap.add_argument("--x86-sha256", default="")
    ap.add_argument("--arm-sha256", default="")
    args = ap.parse_args()

    current = load(args.baseline)
    validate(current)
    if args.self_test:
        self_test(current)
        return 0
    if args.simulate:
        try:
            next_base = simulate(
                current,
                args.sha,
                args.ci_digest,
                args.x86_sha256 or None,
                args.arm_sha256 or None,
            )
        except ValueError as exc:
            print(f"simulate error: {exc}", file=sys.stderr)
            return 2
        payloads = target_payloads(next_base)
        if args.write:
            args.baseline.write_text(
                json.dumps(next_base, indent=2, sort_keys=True) + "\n"
            )
        print(
            json.dumps(
                {"baseline": next_base, "payloads": payloads}, indent=2, sort_keys=True
            )
        )
        return 0
    if args.check or args.write:
        try:
            upstream = fetch_upstream()
        except (urllib.error.URLError, ValueError, KeyError) as exc:
            print(f"upstream error: {exc}", file=sys.stderr)
            return 2
        same = (
            current["aura"]["commit_sha"] == upstream["commit_sha"]
            and current["aura_ci"]["digest"] == upstream["aura_ci_digest"]
        )
        if same:
            print("baseline up to date")
            return 0
        next_base = make_baseline(current, upstream)
        payloads = target_payloads(next_base)
        if args.write:
            args.baseline.write_text(
                json.dumps(next_base, indent=2, sort_keys=True) + "\n"
            )
        print(
            json.dumps(
                {"baseline": next_base, "payloads": payloads}, indent=2, sort_keys=True
            )
        )
        return 0
    ap.print_help()
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
