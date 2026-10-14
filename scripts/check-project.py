"""Check maintained Python, JSON and local Markdown links without model imports."""

from __future__ import annotations

import ast
import json
import re
from pathlib import Path
from urllib.parse import unquote, urlsplit


def markdown_files(root: Path) -> list[Path]:
    return [root / name for name in ("README.md", "CONTRIBUTING.md", "LICENSE-DOCS.md")] + sorted(
        (root / "docs").rglob("*.md")
    )


def prose_lines(text: str):
    """Exclude fenced and inline code, where paths are examples rather than links."""
    fence = None
    for number, line in enumerate(text.splitlines(), 1):
        marker = re.match(r"^ {0,3}(`{3,}|~{3,})(.*)$", line)
        if fence:
            if marker and marker[1][0] == fence[0] and len(marker[1]) >= fence[1] and not marker[2].strip():
                fence = None
            continue
        if marker:
            fence = (marker[1][0], len(marker[1]))
            continue
        yield number, re.sub(r"(`+).*?\1", "", line)


def link_targets(line: str):
    """Read inline links/images and reference definitions used by the tutorials."""
    starts = [match.end() for match in re.finditer(r"!?\[[^\]\n]*\]\(\s*", line)]
    reference = re.match(r"^ {0,3}\[(?!\^)[^\]]+\]:\s*", line)
    if reference:
        starts.append(reference.end())
    for start in starts:
        if start >= len(line):
            continue
        if line[start] == "<":
            end = line.find(">", start + 1)
            if end != -1:
                yield line[start + 1 : end]
            continue
        depth = 0
        cursor = start
        while cursor < len(line):
            char = line[cursor]
            if char == "\\" and cursor + 1 < len(line):
                cursor += 2
                continue
            if char == "(":
                depth += 1
            elif char == ")":
                if depth == 0:
                    break
                depth -= 1
            elif char.isspace() and depth == 0:
                break
            cursor += 1
        if cursor > start:
            yield re.sub(r"\\([\\`*_{}\[\]()#+\-.!<> ])", r"\1", line[start:cursor])


def reject_json_constant(value: str):
    raise ValueError(f"Non-standard JSON constant: {value}")


def check_project(root: Path) -> tuple[list[str], dict[str, int]]:
    root = root.resolve()
    errors = []
    counts = {"python": 0, "json": 0, "markdown": 0, "local_links": 0}

    for path in sorted((root / "scripts").rglob("*.py")):
        counts["python"] += 1
        try:
            ast.parse(path.read_text(encoding="utf-8-sig"), filename=str(path.relative_to(root)))
        except (OSError, UnicodeError, SyntaxError) as error:
            errors.append(f"{path.relative_to(root)}: {error}")

    for name in ("workspace.example.json", "docs/model-sources.json"):
        counts["json"] += 1
        try:
            json.loads((root / name).read_text(encoding="utf-8-sig"), parse_constant=reject_json_constant)
        except (OSError, UnicodeError, ValueError) as error:
            errors.append(f"{name}: {error}")

    for path in markdown_files(root):
        counts["markdown"] += 1
        try:
            source = path.read_text(encoding="utf-8-sig")
        except (OSError, UnicodeError) as error:
            errors.append(f"{path.relative_to(root)}: {error}")
            continue
        for number, line in prose_lines(source):
            for target in link_targets(line):
                location = f"{path.relative_to(root)}:{number}"
                if re.match(r"^[A-Za-z]:[/\\]", target):
                    errors.append(f"{location}: personal absolute link: {target}")
                    continue
                try:
                    parsed = urlsplit(target)
                except ValueError as error:
                    errors.append(f"{location}: malformed link: {target} ({error})")
                    continue
                if parsed.scheme or parsed.netloc or not parsed.path:
                    continue
                counts["local_links"] += 1
                destination = (path.parent / unquote(parsed.path)).resolve()
                if not destination.is_relative_to(root):
                    errors.append(f"{location}: link leaves the project: {target}")
                elif not destination.exists():
                    errors.append(f"{location}: missing local link: {target}")
    return errors, counts


def main() -> int:
    errors, counts = check_project(Path(__file__).resolve().parent.parent)
    print("Checked " + ", ".join(f"{value} {key}" for key, value in counts.items()) + ".")
    for error in errors:
        print(f"ERROR: {error}")
    if errors:
        print(f"Project checks failed: {len(errors)} error(s).")
        return 1
    print("Project checks passed. External URLs and heading anchors are not checked.")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
