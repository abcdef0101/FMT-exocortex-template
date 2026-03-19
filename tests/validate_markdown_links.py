#!/usr/bin/env python3
from __future__ import annotations

import re
import sys
from collections import Counter
from pathlib import Path
from urllib.parse import unquote, urlparse


ROOT = Path(__file__).resolve().parents[1]
LINK_RE = re.compile(r"(?<!!)(?P<all>\[(?P<label>[^\]]+)\]\((?P<target>[^)]+)\))")
FENCE_RE = re.compile(r"^(```|~~~)")
HEADING_RE = re.compile(r"^(#{1,6})\s+(.*)$")
SUMMARY_RE = re.compile(r"<summary>\s*(?:<b>)?(.*?)(?:</b>)?\s*</summary>", re.IGNORECASE)
SCHEMES = {"http", "https", "mailto", "tel"}


def iter_markdown_files() -> list[Path]:
    return sorted(
        p for p in ROOT.rglob("*.md") if ".git" not in p.parts and "test_helper" not in p.parts
    )


def strip_code_fences(text: str) -> list[str]:
    lines: list[str] = []
    in_fence = False
    for line in text.splitlines():
        if FENCE_RE.match(line.strip()):
            in_fence = not in_fence
            lines.append("")
            continue
        lines.append("") if in_fence else lines.append(line)
    return lines


def slugify_heading(text: str) -> str:
    text = text.strip().lower()
    buf = []
    prev_dash = False
    for ch in text:
        if ch.isalnum() or ch in {"_"} or ord(ch) > 127 and ch.isalpha():
            buf.append(ch)
            prev_dash = False
        elif ch in {" ", "-"}:
            if not prev_dash:
                buf.append("-")
                prev_dash = True
        # punctuation is dropped
    slug = "".join(buf).strip("-")
    slug = re.sub(r"-+", "-", slug)
    return slug


def extract_heading_anchors(path: Path) -> set[str]:
    text = path.read_text(encoding="utf-8", errors="ignore")
    counts: Counter[str] = Counter()
    anchors: set[str] = set()
    for line in strip_code_fences(text):
        m = HEADING_RE.match(line)
        heading = None
        if m:
            heading = m.group(2).strip()
        else:
            sm = SUMMARY_RE.search(line)
            if sm:
                heading = re.sub(r"<[^>]+>", "", sm.group(1)).strip()
        if heading:
            slug = slugify_heading(heading)
            if not slug:
                continue
            n = counts[slug]
            counts[slug] += 1
            anchors.add(slug if n == 0 else f"{slug}-{n}")
    return anchors


def normalize_target(target: str) -> str:
    target = target.strip()
    if target.startswith("<") and target.endswith(">"):
        target = target[1:-1]
    return unquote(target)


def should_check(target: str) -> bool:
    parsed = urlparse(target)
    if parsed.scheme in SCHEMES:
        return False
    return True


def resolve_target(src: Path, target: str) -> tuple[Path | None, str | None, bool]:
    target = normalize_target(target)
    if not should_check(target):
        return None, None, False
    if target.startswith("#"):
        return src, target[1:], True
    path_part, frag = (target.split("#", 1) + [None])[:2] if "#" in target else (target, None)
    if not path_part:
        return src, frag, True
    resolved = (src.parent / path_part).resolve()
    try:
        resolved.relative_to(ROOT)
    except ValueError:
        return None, None, False
    return resolved, frag, True


def validate() -> list[str]:
    errors: list[str] = []
    anchor_cache: dict[Path, set[str]] = {}
    for md in iter_markdown_files():
        text = md.read_text(encoding="utf-8", errors="ignore")
        for lineno, line in enumerate(strip_code_fences(text), start=1):
            for match in LINK_RE.finditer(line):
                target = match.group("target")
                resolved, fragment, check = resolve_target(md, target)
                if not check:
                    continue
                if resolved is None:
                    continue
                if target.endswith("/"):
                    if not resolved.exists() or not resolved.is_dir():
                        errors.append(f"{md.relative_to(ROOT)}:{lineno} -> missing directory: {target}")
                    continue
                if resolved.is_dir():
                    continue
                if not resolved.exists():
                    errors.append(f"{md.relative_to(ROOT)}:{lineno} -> missing file: {target}")
                    continue
                if fragment:
                    fragment = slugify_heading(fragment)
                    if resolved not in anchor_cache:
                        anchor_cache[resolved] = extract_heading_anchors(resolved)
                    if fragment not in anchor_cache[resolved]:
                        errors.append(
                            f"{md.relative_to(ROOT)}:{lineno} -> missing anchor '#{fragment}' in {resolved.relative_to(ROOT)}"
                        )
    return errors


def main() -> int:
    errors = validate()
    if errors:
        print("Invalid markdown links found:")
        for err in errors:
            print(f"- {err}")
        return 1
    print("All local markdown links are valid.")
    return 0


if __name__ == "__main__":
    sys.exit(main())
