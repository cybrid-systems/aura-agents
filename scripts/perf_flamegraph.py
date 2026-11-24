#!/usr/bin/env python3
"""Collapse `perf script` samples and render a static on-CPU flamegraph.

The CI image has no Perl flamegraph scripts, so this keeps the #14
artifact path self-contained: perf script -> folded stacks -> SVG. It
does not sample anything itself and does not touch the target.
"""
from __future__ import annotations

import argparse
import html
import re
import sys
from collections import Counter
from dataclasses import dataclass, field


SAMPLE_RE = re.compile(r"^\S+\s+\d+\s+[^:]+:")
FRAME_RE = re.compile(r"^\s+[0-9a-fA-F]+\s+(.*?)\s+\(([^)]*)\)\s*$")


def parse_perf_script(text: str) -> Counter[tuple[str, ...]]:
    counts: Counter[tuple[str, ...]] = Counter()
    stack: list[str] = []

    def flush() -> None:
        nonlocal stack
        if stack:
            # perf script prints leaf first; folded stacks are root first.
            counts[tuple(reversed(stack))] += 1
        stack = []

    for raw in text.splitlines():
        if not raw.strip():
            flush()
            continue
        if not raw[0].isspace():
            flush()
            if SAMPLE_RE.match(raw):
                continue
        match = FRAME_RE.match(raw)
        if match:
            symbol = match.group(1).strip()
        else:
            symbol = " ".join(raw.split())
        if not symbol:
            continue
        symbol = re.sub(r"\+0x[0-9a-fA-F]+$", "", symbol)
        symbol = symbol.replace(";", ":")
        stack.append(symbol)
    flush()
    return counts


def write_folded(counts: Counter[tuple[str, ...]], path: str) -> None:
    with open(path, "w", encoding="utf-8") as handle:
        for stack in sorted(counts):
            handle.write(f"{';'.join(stack)} {counts[stack]}\n")


@dataclass
class Node:
    name: str
    count: int = 0
    children: dict[str, "Node"] = field(default_factory=dict)


def build_tree(counts: Counter[tuple[str, ...]]) -> Node:
    root = Node("all")
    for stack, count in counts.items():
        node = root
        node.count += count
        for name in stack:
            node = node.children.setdefault(name, Node(name))
            node.count += count
    return root


PALETTE = [
    "#6b8e23", "#4682b4", "#b8860b", "#8f6c9e", "#2e8b57",
    "#cd5c5c", "#5f9ea0", "#a0522d", "#7b68ee", "#708090",
]


def render_svg(root: Node, path: str, title: str, width: int = 1200) -> None:
    row_height = 18
    margin_top = 28
    max_depth = 0

    def depth(node: Node, level: int = 0) -> None:
        nonlocal max_depth
        max_depth = max(max_depth, level)
        for child in node.children.values():
            depth(child, level + 1)

    depth(root)
    height = margin_top + (max_depth + 1) * row_height + 10
    total = max(1, root.count)
    parts = [
        f'<svg xmlns="http://www.w3.org/2000/svg" width="{width}" height="{height}" '
        f'viewBox="0 0 {width} {height}" role="img" aria-label="{html.escape(title)}">',
        f'<text x="8" y="18" font-size="14" font-family="monospace" fill="#222">{html.escape(title)} '
        f'({total} samples)</text>',
    ]

    def layout(node: Node, x: float, level: int) -> None:
        span = width * (node.count / total)
        if level > 0:
            y = margin_top + level * row_height
            color = PALETTE[(level + sum(ord(c) for c in node.name[:3])) % len(PALETTE)]
            label = node.name if span > 44 else (node.name[:8] + "…" if span > 20 else "")
            parts.append(
                f'<rect x="{x:.2f}" y="{y}" width="{max(0.4, span - 0.4):.2f}" '
                f'height="{row_height - 1}" fill="{color}" fill-opacity="0.85">'
                f'<title>{html.escape(node.name)} ({node.count})</title></rect>'
            )
            if label:
                parts.append(
                    f'<text x="{x + 3:.2f}" y="{y + 12}" font-size="11" '
                    f'font-family="monospace" fill="#fff">{html.escape(label)}</text>'
                )
        child_x = x
        for name in sorted(node.children):
            child = node.children[name]
            layout(child, child_x, level + 1)
            child_x += width * (child.count / total)

    layout(root, 0.0, 0)
    parts.append("</svg>")
    with open(path, "w", encoding="utf-8") as handle:
        handle.write("\n".join(parts) + "\n")


def main(argv: list[str] | None = None) -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--script", required=True, help="perf script output")
    parser.add_argument("--folded", required=True, help="folded stacks output")
    parser.add_argument("--svg", required=True, help="SVG output")
    parser.add_argument("--title", default="on-CPU")
    parser.add_argument("--width", type=int, default=1200)
    args = parser.parse_args(argv)
    try:
        with open(args.script, "r", encoding="utf-8", errors="replace") as handle:
            counts = parse_perf_script(handle.read())
    except OSError as exc:
        print(f"perf_flamegraph: {exc}", file=sys.stderr)
        return 2
    if not counts:
        print("perf_flamegraph: no samples parsed", file=sys.stderr)
        return 3
    write_folded(counts, args.folded)
    render_svg(build_tree(counts), args.svg, args.title, args.width)
    print(f"perf_flamegraph: samples={sum(counts.values())} stacks={len(counts)}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
