#!/usr/bin/env python3
"""
lint_skill.py — Deterministic linter for Claude Code skills.

Usage:
    python lint_skill.py <path-to-skill-directory>

Exits 0 if only warnings or no findings; exits 1 if any ERROR-level finding.
"""

import os
import re
import sys
from pathlib import Path
from typing import List, Tuple

# ----------------------------------------------------------------------------
# Configuration constants
# ----------------------------------------------------------------------------

SKILL_MD_LINE_WARN = 400
SKILL_MD_LINE_ERROR = 500
REFERENCE_TOC_LINE_THRESHOLD = 100
DESCRIPTION_MAX_CHARS = 1024
NAME_MAX_CHARS = 64
DESCRIPTION_FRONT_LOAD_CHARS = 250

ALL_CAPS_WARN_COUNT = 5
RIGID_DIRECTIVE_WARN_COUNT = 8  # "MUST" / "NEVER" / "ALWAYS" combined

RESERVED_NAMES = {"anthropic", "claude"}
NAME_PATTERN = re.compile(r"^[a-z][a-z0-9-]{0,63}$")

FIRST_PERSON_PATTERNS = [
    re.compile(r"\bI can\b", re.IGNORECASE),
    re.compile(r"\bI will\b", re.IGNORECASE),
    re.compile(r"\bI'll\b", re.IGNORECASE),
    re.compile(r"\blet me\b", re.IGNORECASE),
]

SECOND_PERSON_PATTERNS = [
    re.compile(r"\byou can use\b", re.IGNORECASE),
    re.compile(r"\byou should\b", re.IGNORECASE),
    re.compile(r"\byou will\b", re.IGNORECASE),
    re.compile(r"\byour task\b", re.IGNORECASE),
]

# Description should include some "when" trigger phrase to help selection.
WHEN_TRIGGER_PATTERNS = [
    re.compile(r"\buse when\b", re.IGNORECASE),
    re.compile(r"\bwhen the user\b", re.IGNORECASE),
    re.compile(r"\bwhen working\b", re.IGNORECASE),
    re.compile(r"\bwhenever\b", re.IGNORECASE),
    re.compile(r"\btriggers? on\b", re.IGNORECASE),
    re.compile(r"\bactivates? when\b", re.IGNORECASE),
]

VAGUE_OPENERS = [
    re.compile(r"^\s*helps? with\b", re.IGNORECASE),
    re.compile(r"^\s*does stuff\b", re.IGNORECASE),
    re.compile(r"^\s*useful for\b", re.IGNORECASE),
]

TIME_SENSITIVE_PATTERNS = [
    re.compile(r"\bas of (?:january|february|march|april|may|june|july|august|september|october|november|december|20\d\d)\b", re.IGNORECASE),
    re.compile(r"\bbefore (?:january|february|march|april|may|june|july|august|september|october|november|december)\s+20\d\d\b", re.IGNORECASE),
    re.compile(r"\bcurrently \(as of\b", re.IGNORECASE),
    re.compile(r"\bin 20\d\d,\s", re.IGNORECASE),
]

ALL_CAPS_WORD = re.compile(r"\b[A-Z]{4,}\b")
RIGID_DIRECTIVE = re.compile(r"\b(?:MUST|NEVER|ALWAYS|CRITICAL|REQUIRED)\b")

WINDOWS_PATH = re.compile(r"[a-zA-Z_./-]+\\[a-zA-Z_./-]+")

MARKDOWN_LINK = re.compile(r"\[([^\]]+)\]\(([^)]+)\)")

TOC_HEADER_PATTERNS = [
    re.compile(r"^##+\s+(table of contents|toc|contents)\b", re.IGNORECASE | re.MULTILINE),
]

# ----------------------------------------------------------------------------
# Finding model
# ----------------------------------------------------------------------------

class Finding:
    __slots__ = ("severity", "file", "line", "code", "message")

    def __init__(self, severity: str, file: str, line: int, code: str, message: str):
        self.severity = severity  # ERROR | WARN | INFO
        self.file = file
        self.line = line
        self.code = code
        self.message = message

    def format(self) -> str:
        loc = f"{self.file}"
        if self.line > 0:
            loc += f":{self.line}"
        return f"{loc:40s} {self.severity:5s} {self.code:20s} {self.message}"


# ----------------------------------------------------------------------------
# Frontmatter parsing
# ----------------------------------------------------------------------------

def parse_frontmatter(text: str) -> Tuple[dict, int]:
    """Returns (frontmatter_dict, body_start_line). Empty dict if no frontmatter."""
    lines = text.split("\n")
    if not lines or lines[0].strip() != "---":
        return {}, 0

    end_idx = None
    for i in range(1, len(lines)):
        if lines[i].strip() == "---":
            end_idx = i
            break

    if end_idx is None:
        return {}, 0

    fm = {}
    current_key = None
    current_value_lines = []
    for line in lines[1:end_idx]:
        m = re.match(r"^([a-zA-Z_-][a-zA-Z0-9_-]*)\s*:\s*(.*)$", line)
        if m and not line.startswith(" "):
            if current_key is not None:
                fm[current_key] = "\n".join(current_value_lines).strip()
            current_key = m.group(1)
            current_value_lines = [m.group(2)]
        else:
            if current_key is not None:
                current_value_lines.append(line)
    if current_key is not None:
        fm[current_key] = "\n".join(current_value_lines).strip()

    # Strip wrapping quotes
    for k, v in list(fm.items()):
        if len(v) >= 2 and v[0] == v[-1] and v[0] in '"\'':
            fm[k] = v[1:-1]

    return fm, end_idx + 1


# ----------------------------------------------------------------------------
# Frontmatter checks
# ----------------------------------------------------------------------------

def check_frontmatter(fm: dict, findings: List[Finding]) -> None:
    file = "SKILL.md"

    # name
    name = fm.get("name", "")
    if not name:
        findings.append(Finding("ERROR", file, 1, "FM001", "Missing required `name` field in frontmatter"))
    else:
        if len(name) > NAME_MAX_CHARS:
            findings.append(Finding("ERROR", file, 1, "FM002", f"`name` exceeds {NAME_MAX_CHARS} characters ({len(name)})"))
        if not NAME_PATTERN.match(name):
            findings.append(Finding("ERROR", file, 1, "FM003", f"`name` must match ^[a-z][a-z0-9-]{{0,63}}$ (got: {name!r})"))
        for reserved in RESERVED_NAMES:
            if reserved in name.lower().split("-"):
                findings.append(Finding("ERROR", file, 1, "FM004", f"`name` contains reserved word {reserved!r}"))

    # description
    desc = fm.get("description", "")
    if not desc:
        findings.append(Finding("ERROR", file, 1, "FM010", "Missing required `description` field in frontmatter"))
        return

    if len(desc) > DESCRIPTION_MAX_CHARS:
        findings.append(Finding("ERROR", file, 1, "FM011", f"`description` exceeds {DESCRIPTION_MAX_CHARS} chars ({len(desc)})"))

    # Person check
    for pat in FIRST_PERSON_PATTERNS:
        if pat.search(desc):
            findings.append(Finding("ERROR", file, 1, "FM012", f"`description` contains first-person language matching /{pat.pattern}/ — use third person"))
            break

    for pat in SECOND_PERSON_PATTERNS:
        if pat.search(desc):
            findings.append(Finding("WARN", file, 1, "FM013", f"`description` contains second-person language matching /{pat.pattern}/ — prefer third person"))
            break

    # WHEN trigger
    if not any(pat.search(desc) for pat in WHEN_TRIGGER_PATTERNS):
        findings.append(Finding("WARN", file, 1, "FM014", "`description` is missing a 'when' trigger phrase (e.g. 'use when', 'when the user', 'whenever') — Claude needs an explicit when-to-use signal"))

    # Vague opener
    for pat in VAGUE_OPENERS:
        if pat.search(desc):
            findings.append(Finding("WARN", file, 1, "FM015", f"`description` opens vaguely matching /{pat.pattern}/ — be specific about what the skill does"))
            break

    # Front-loading: at least one when-trigger phrase or specific keyword in first 250 chars
    desc_head = desc[:DESCRIPTION_FRONT_LOAD_CHARS]
    if len(desc) > DESCRIPTION_FRONT_LOAD_CHARS and not any(pat.search(desc_head) for pat in WHEN_TRIGGER_PATTERNS):
        findings.append(Finding("WARN", file, 1, "FM016", f"Trigger keywords appear after the {DESCRIPTION_FRONT_LOAD_CHARS}-char truncation point — Claude Code may not see them in the listing"))


# ----------------------------------------------------------------------------
# Body checks
# ----------------------------------------------------------------------------

def check_body(body: str, body_start_line: int, findings: List[Finding]) -> None:
    file = "SKILL.md"
    lines = body.split("\n")
    line_count = len(lines)
    total_lines = body_start_line + line_count

    # Line count
    if total_lines >= SKILL_MD_LINE_ERROR:
        findings.append(Finding("ERROR", file, total_lines, "BD001", f"SKILL.md is {total_lines} lines (limit: {SKILL_MD_LINE_ERROR}) — split into references/"))
    elif total_lines >= SKILL_MD_LINE_WARN:
        findings.append(Finding("WARN", file, total_lines, "BD001", f"SKILL.md is {total_lines} lines (target: <{SKILL_MD_LINE_WARN}) — consider splitting into references/"))

    # Person check on body
    body_first_person = sum(1 for pat in FIRST_PERSON_PATTERNS for _ in pat.finditer(body))
    if body_first_person > 0:
        findings.append(Finding("WARN", file, body_start_line, "BD002", f"{body_first_person} first-person references in body — prefer third-person imperative"))

    # ALL-CAPS detection (excluding code blocks)
    body_no_code = strip_code_blocks(body)
    all_caps_matches = ALL_CAPS_WORD.findall(body_no_code)
    # Filter out common acronyms that aren't really shouting
    common_acronyms = {
        # File formats and protocols
        "JSON", "YAML", "HTML", "CSS", "HTTP", "HTTPS", "REST", "GRPC", "URL", "URI",
        "PDF", "DOCX", "XLSX", "PPTX", "CSV", "TSV", "XML", "SVG", "PNG", "JPG",
        # Languages and frameworks
        "SQL", "SKILL", "API", "CLI", "SDK", "MCP", "LLM", "TTS", "STT",
        # Testing and workflow terminology
        "TDD", "BDD", "DDD", "RED", "GREEN", "REFACTOR", "STOP", "PASS", "FAIL",
        "ALL", "NONE", "TODO", "FIXME", "NOTE", "HACK", "XXX",
        # Security / audit
        "OWASP", "CVE", "CWE", "DDOS", "XSS", "CSRF", "CORS", "SSRF", "IDOR",
        "PII", "PHI", "RBAC", "ACL", "CSP", "HSTS",
        # Severity / priority labels (code review, security audit, incident response)
        "CRITICAL", "HIGH", "MEDIUM", "LOW", "SEVERE", "BLOCKER", "MAJOR", "MINOR",
        "P0", "P1", "P2", "P3", "SEV1", "SEV2", "SEV3",
        # Git / VCS
        "DIFF", "HEAD", "MERGE", "COMMIT",
    }
    real_caps = [w for w in all_caps_matches if w not in common_acronyms]
    if len(real_caps) > ALL_CAPS_WARN_COUNT:
        sample = ", ".join(real_caps[:5])
        findings.append(Finding("WARN", file, body_start_line, "BD003", f"{len(real_caps)} ALL-CAPS words detected (e.g., {sample}) — modern models overtrigger on emphatic language"))

    # Rigid directives
    rigid_count = len(RIGID_DIRECTIVE.findall(body_no_code))
    if rigid_count > RIGID_DIRECTIVE_WARN_COUNT:
        findings.append(Finding("WARN", file, body_start_line, "BD004", f"{rigid_count} rigid directives (MUST/NEVER/ALWAYS/CRITICAL/REQUIRED) — explain the why instead"))

    # Time-sensitive language and Windows-style paths (skip inside fenced code blocks)
    in_code_block = False
    for i, line in enumerate(lines):
        stripped = line.lstrip()
        if stripped.startswith("```"):
            in_code_block = not in_code_block
            continue
        if in_code_block:
            continue

        for pat in TIME_SENSITIVE_PATTERNS:
            if pat.search(line):
                findings.append(Finding("WARN", file, body_start_line + i, "BD005", f"Time-sensitive phrase: {line.strip()[:80]}"))
                break

        if WINDOWS_PATH.search(line):
            findings.append(Finding("WARN", file, body_start_line + i, "BD006", "Windows-style backslash path — use forward slashes"))


def strip_code_blocks(text: str) -> str:
    """Remove fenced code blocks so checks don't false-positive on code."""
    return re.sub(r"```.*?```", "", text, flags=re.DOTALL)


# ----------------------------------------------------------------------------
# Structural checks (links, references, orphans)
# ----------------------------------------------------------------------------

def check_links_and_references(skill_dir: Path, body: str, findings: List[Finding]) -> None:
    """Verify markdown links to local files resolve, and detect chained references."""
    referenced_files = set()
    skill_md_path = skill_dir / "SKILL.md"

    for m in MARKDOWN_LINK.finditer(body):
        link = m.group(2).strip()
        # Skip URLs and anchors
        if link.startswith(("http://", "https://", "#", "mailto:")):
            continue
        # Strip fragment
        link_path = link.split("#")[0]
        if not link_path:
            continue

        target = (skill_dir / link_path).resolve()
        try:
            target.relative_to(skill_dir.resolve())
        except ValueError:
            findings.append(Finding("WARN", "SKILL.md", 0, "ST001", f"Link points outside skill directory: {link}"))
            continue

        if not target.exists():
            findings.append(Finding("ERROR", "SKILL.md", 0, "ST002", f"Broken link to local file: {link}"))
        else:
            try:
                rel = target.relative_to(skill_dir.resolve())
                referenced_files.add(str(rel))
            except ValueError:
                pass

            # Check for chained references (depth > 1)
            if target.suffix == ".md" and target.name != "SKILL.md":
                check_reference_depth(skill_dir, target, findings, depth=1)

    # Check for orphan files in scripts/, references/, assets/
    for subdir in ("scripts", "references", "assets", "agents"):
        d = skill_dir / subdir
        if not d.is_dir():
            continue
        for f in d.rglob("*"):
            if not f.is_file():
                continue
            if f.name.startswith(".") or f.name == "__pycache__":
                continue
            rel = str(f.relative_to(skill_dir))
            # Heuristic: file is referenced if its name appears in body OR full rel path appears
            if f.name not in body and rel not in body and rel.replace("\\", "/") not in body:
                findings.append(Finding("WARN", rel, 0, "ST003", f"File not referenced from SKILL.md (potential orphan): {rel}"))


def check_reference_depth(skill_dir: Path, ref_file: Path, findings: List[Finding], depth: int) -> None:
    """Detect chained references (SKILL.md → ref1.md → ref2.md)."""
    if depth > 1:
        return  # Only check first level
    try:
        text = ref_file.read_text(encoding="utf-8", errors="replace")
    except OSError:
        return

    rel_parent = str(ref_file.relative_to(skill_dir))
    for m in MARKDOWN_LINK.finditer(text):
        link = m.group(2).strip()
        if link.startswith(("http://", "https://", "#", "mailto:")):
            continue
        link_path = link.split("#")[0]
        if not link_path:
            continue
        target = (ref_file.parent / link_path).resolve()
        try:
            target.relative_to(skill_dir.resolve())
        except ValueError:
            continue
        if target.exists() and target.suffix == ".md" and target.name != "SKILL.md":
            findings.append(Finding("WARN", rel_parent, 0, "ST004", f"Reference file links to another reference ({link}) — Claude may partial-read; link directly from SKILL.md instead"))


# ----------------------------------------------------------------------------
# Reference file checks
# ----------------------------------------------------------------------------

def check_references_dir(skill_dir: Path, findings: List[Finding]) -> None:
    """Check that long reference files have a TOC."""
    refs = skill_dir / "references"
    if not refs.is_dir():
        return
    for f in refs.rglob("*.md"):
        try:
            text = f.read_text(encoding="utf-8", errors="replace")
        except OSError:
            continue
        line_count = text.count("\n") + 1
        if line_count >= REFERENCE_TOC_LINE_THRESHOLD:
            has_toc = any(pat.search(text) for pat in TOC_HEADER_PATTERNS)
            if not has_toc:
                rel = str(f.relative_to(skill_dir))
                findings.append(Finding("WARN", rel, 0, "RF001", f"Reference file is {line_count} lines but has no table of contents"))


# ----------------------------------------------------------------------------
# Main
# ----------------------------------------------------------------------------

def lint_skill(skill_dir: Path) -> List[Finding]:
    findings: List[Finding] = []

    if not skill_dir.exists():
        findings.append(Finding("ERROR", str(skill_dir), 0, "SK001", "Skill directory does not exist"))
        return findings

    skill_md = skill_dir / "SKILL.md"
    if not skill_md.exists():
        findings.append(Finding("ERROR", str(skill_dir), 0, "SK002", "Missing SKILL.md (skill entrypoint)"))
        return findings

    try:
        text = skill_md.read_text(encoding="utf-8", errors="replace")
    except OSError as e:
        findings.append(Finding("ERROR", "SKILL.md", 0, "SK003", f"Cannot read SKILL.md: {e}"))
        return findings

    fm, body_start_line = parse_frontmatter(text)
    body = "\n".join(text.split("\n")[body_start_line:]) if body_start_line > 0 else text

    if not fm:
        findings.append(Finding("ERROR", "SKILL.md", 1, "FM000", "Missing or malformed YAML frontmatter (must be wrapped in --- markers at top of file)"))
    else:
        check_frontmatter(fm, findings)

    check_body(body, body_start_line, findings)
    check_links_and_references(skill_dir, body, findings)
    check_references_dir(skill_dir, findings)

    return findings


def format_report(findings: List[Finding], skill_dir: Path) -> str:
    if not findings:
        return f"✓ {skill_dir.name}: no issues found\n"

    by_severity = {"ERROR": [], "WARN": [], "INFO": []}
    for f in findings:
        by_severity[f.severity].append(f)

    lines = [f"Skill audit (lint): {skill_dir.name}", "=" * 60]
    for sev in ("ERROR", "WARN", "INFO"):
        items = by_severity[sev]
        if not items:
            continue
        lines.append(f"\n{sev} ({len(items)})")
        lines.append("-" * 60)
        for f in items:
            lines.append("  " + f.format())

    lines.append("")
    lines.append(f"Total: {len(by_severity['ERROR'])} error(s), {len(by_severity['WARN'])} warning(s)")
    return "\n".join(lines) + "\n"


def main() -> int:
    if len(sys.argv) != 2:
        print("Usage: lint_skill.py <path-to-skill-directory>", file=sys.stderr)
        return 2

    skill_dir = Path(sys.argv[1]).resolve()
    findings = lint_skill(skill_dir)
    print(format_report(findings, skill_dir))

    has_error = any(f.severity == "ERROR" for f in findings)
    return 1 if has_error else 0


if __name__ == "__main__":
    sys.exit(main())
