#!/usr/bin/env python3
"""
Background knowledge extractor for Sentinel.

Spawned by hooks/optional/stop-pattern-extractor.sh after a session ends.
Reads the session transcript + the modified-files list, calls the Anthropic
Messages API with a structured tool-use schema, and writes any extracted
items to vault/{patterns/learned,gotchas,investigations,decisions}/.

Why a separate Python script instead of a shell hook:
  Stop-hook stdout never reaches Claude (per the Claude Code hooks spec — see
  https://code.claude.com/docs/en/hooks "Exit code output"), so the legacy
  approach of cat-ing a "please extract patterns" prompt to stdout was inert.
  This script does the extraction itself, deterministically, in the background.

Hard requirements:
  - ANTHROPIC_API_KEY env var
  - Python 3.8+ (stdlib only — no third-party deps)

Inputs (all required):
  --transcript     Path to the session JSONL transcript
  --modified-files Path to .sentinel/sessions/<id>/modified-files.txt
  --vault          Path to the vault directory (e.g. <project>/vault)

Optional:
  --model          Anthropic model id (default: claude-haiku-4-5)
  --max-tokens     Response cap (default: 4096)
  --max-input-chars Transcript truncation cap (default: 60000)
  --dry-run        Build the request, log the prompt, but do not call the API
                   or write any files.

Exits 0 on success or graceful skip. Non-zero exits are reserved for
unexpected runtime errors so the spawning hook can surface them in the log.
"""
from __future__ import annotations

import argparse
import datetime as dt
import json
import os
import re
import sys
import urllib.error
import urllib.request
from pathlib import Path
from typing import Any

API_URL = "https://api.anthropic.com/v1/messages"
ANTHROPIC_VERSION = "2023-06-01"
DEFAULT_MODEL = "claude-haiku-4-5"

# Tool-use schema. Forcing tool_choice on this tool guarantees a structured
# response — no JSON parsing of free-form text required.
EXTRACT_TOOL = {
    "name": "record_session_knowledge",
    "description": (
        "Record reusable knowledge items extracted from the session. Be "
        "conservative — only emit items that are genuinely reusable, "
        "non-obvious, and grounded in events from this session. If the "
        "session produced no genuine learnings, emit empty arrays."
    ),
    "input_schema": {
        "type": "object",
        "properties": {
            "patterns": {
                "type": "array",
                "description": (
                    "Reusable engineering patterns discovered or applied. "
                    "Each pattern should be a non-obvious rule of thumb, "
                    "not a restatement of the immediate task."
                ),
                "items": {
                    "type": "object",
                    "properties": {
                        "title": {"type": "string"},
                        "area": {
                            "type": "string",
                            "description": "Module or domain (e.g. 'auth', 'caching').",
                        },
                        "description": {
                            "type": "string",
                            "description": "1-3 sentences. State the rule, then why.",
                        },
                    },
                    "required": ["title", "area", "description"],
                },
            },
            "gotchas": {
                "type": "array",
                "description": (
                    "Pitfalls discovered — surprising failure modes that "
                    "future sessions should avoid."
                ),
                "items": {
                    "type": "object",
                    "properties": {
                        "title": {"type": "string"},
                        "what_goes_wrong": {"type": "string"},
                        "how_to_avoid": {"type": "string"},
                    },
                    "required": ["title", "what_goes_wrong", "how_to_avoid"],
                },
            },
            "investigations": {
                "type": "array",
                "description": (
                    "Bug investigations conducted during the session. "
                    "Include only investigations that produced real findings, "
                    "not routine debugging."
                ),
                "items": {
                    "type": "object",
                    "properties": {
                        "title": {"type": "string"},
                        "area": {"type": "string"},
                        "severity": {
                            "type": "string",
                            "enum": ["critical", "high", "medium", "low"],
                        },
                        "symptom": {"type": "string"},
                        "root_cause": {"type": "string"},
                        "fix": {"type": "string"},
                        "status": {
                            "type": "string",
                            "enum": ["resolved", "in-progress", "open"],
                        },
                    },
                    "required": [
                        "title",
                        "area",
                        "severity",
                        "symptom",
                        "root_cause",
                        "fix",
                        "status",
                    ],
                },
            },
            "decisions": {
                "type": "array",
                "description": (
                    "Architectural decisions made — emit only when an "
                    "explicit trade-off was discussed and chosen."
                ),
                "items": {
                    "type": "object",
                    "properties": {
                        "title": {"type": "string"},
                        "context": {"type": "string"},
                        "decision": {"type": "string"},
                        "consequences": {"type": "string"},
                    },
                    "required": ["title", "context", "decision", "consequences"],
                },
            },
        },
        "required": ["patterns", "gotchas", "investigations", "decisions"],
    },
}

SYSTEM_PROMPT = """\
You are a knowledge-extraction assistant for the Sentinel vault. You read a
Claude Code session transcript and emit only genuinely reusable knowledge.

Be conservative. Most sessions produce zero items in most categories — that is
expected and correct. Emit a category only when you find something specific,
non-obvious, and grounded in concrete events from this transcript.

Avoid:
- Restating the task ("we added a login form" — not a pattern)
- Generic best practices ("use type hints")
- Speculation about future work
- Items that duplicate something already discussed in the existing vault

Use the record_session_knowledge tool. Always call it. Empty arrays are valid
when nothing reusable emerged.
"""


def slugify(title: str, max_len: int = 60) -> str:
    """Filesystem-safe slug from a title."""
    s = title.lower().strip()
    s = re.sub(r"[^a-z0-9\s-]", "", s)
    s = re.sub(r"[\s_-]+", "-", s).strip("-")
    return s[:max_len] or "untitled"


def load_modified_files(path: Path) -> list[str]:
    if not path.is_file():
        return []
    return [line.strip() for line in path.read_text().splitlines() if line.strip()]


def load_transcript(path: Path, max_chars: int) -> str:
    """
    Read the JSONL transcript and assemble a readable plain-text rendering of
    the most-recent turns, capped at max_chars.

    Strategy: prefer the tail (most recent activity drives extraction quality
    more than session start). If we have headroom, prepend a small slice from
    the start as anchor context.
    """
    if not path.is_file():
        return ""

    rendered_turns: list[str] = []
    try:
        with path.open() as f:
            for raw_line in f:
                raw_line = raw_line.strip()
                if not raw_line:
                    continue
                try:
                    obj = json.loads(raw_line)
                except json.JSONDecodeError:
                    continue
                turn = render_turn(obj)
                if turn:
                    rendered_turns.append(turn)
    except OSError:
        return ""

    if not rendered_turns:
        return ""

    # Take from the tail until we hit the cap.
    tail: list[str] = []
    used = 0
    for turn in reversed(rendered_turns):
        if used + len(turn) > max_chars:
            break
        tail.append(turn)
        used += len(turn) + 2

    return "\n\n".join(reversed(tail))


def render_turn(obj: dict) -> str:
    """Render a single transcript line as readable text. Skip noise."""
    role = obj.get("type") or obj.get("role")
    msg = obj.get("message")
    if not isinstance(msg, dict):
        # Some lines (e.g. summary/sidechain markers) lack a message body.
        return ""

    speaker = msg.get("role") or role or "unknown"
    content = msg.get("content")
    text_parts: list[str] = []

    if isinstance(content, str):
        text_parts.append(content)
    elif isinstance(content, list):
        for block in content:
            if not isinstance(block, dict):
                continue
            btype = block.get("type")
            if btype == "text":
                text_parts.append(block.get("text", ""))
            elif btype == "tool_use":
                tool_name = block.get("name", "?")
                tool_input = block.get("input", {})
                # Render only tool name + a short input preview to keep the
                # transcript dense without including full file contents.
                preview = json.dumps(tool_input, default=str)[:300]
                text_parts.append(f"[tool:{tool_name} input={preview}]")
            elif btype == "tool_result":
                result = block.get("content", "")
                if isinstance(result, list):
                    result = " ".join(
                        b.get("text", "") for b in result if isinstance(b, dict)
                    )
                text_parts.append(f"[tool_result {str(result)[:300]}]")

    text = " ".join(p for p in text_parts if p).strip()
    if not text:
        return ""
    return f"{speaker}: {text}"


def existing_titles(vault: Path, subdir: str) -> set[str]:
    """Slug-set of files already in vault/<subdir>/, used for dedup."""
    d = vault / subdir
    if not d.is_dir():
        return set()
    titles: set[str] = set()
    for f in d.glob("*.md"):
        if f.name.startswith("_"):
            continue
        titles.add(f.stem.lower())
    return titles


def render_pattern(p: dict) -> str:
    """Match the inline-key convention used by scripts/update-confidence.sh."""
    return (
        f"title: {p['title']}\n"
        f"area: {p['area']}\n"
        f"confidence: 0.5\n"
        f"observations: 1\n"
        f"description: {p['description']}\n"
        f"\n"
        f"# {p['title']}\n\n"
        f"{p['description']}\n"
    )


def render_gotcha(g: dict) -> str:
    return (
        f"# {g['title']}\n\n"
        f"## What Goes Wrong\n\n"
        f"{g['what_goes_wrong']}\n\n"
        f"## How to Avoid\n\n"
        f"{g['how_to_avoid']}\n\n"
        f"## Discovered\n\n"
        f"{dt.date.today().isoformat()} via Sentinel auto-extraction.\n"
    )


def render_investigation(i: dict) -> str:
    return (
        f"# Investigation: {i['title']}\n\n"
        f"**Status:** {i['status']}\n"
        f"**Date:** {dt.date.today().isoformat()}\n"
        f"**Area:** {i['area']}\n"
        f"**Severity:** {i['severity']}\n\n"
        f"## Symptom\n\n{i['symptom']}\n\n"
        f"## Root Cause\n\n{i['root_cause']}\n\n"
        f"## Fix\n\n{i['fix']}\n\n"
        f"## Source\n\nAuto-extracted by Sentinel from session transcript.\n"
    )


def render_decision(d: dict) -> str:
    return (
        f"# {d['title']}\n\n"
        f"**Status:** proposed\n"
        f"**Date:** {dt.date.today().isoformat()}\n\n"
        f"## Context\n\n{d['context']}\n\n"
        f"## Decision\n\n{d['decision']}\n\n"
        f"## Consequences\n\n{d['consequences']}\n\n"
        f"## Source\n\nAuto-extracted by Sentinel — review before promoting to "
        f"`accepted`.\n"
    )


def write_items(
    vault: Path,
    payload: dict,
    log_lines: list[str],
) -> dict:
    """
    Write each extracted item to its vault subdir, deduping on slug. Returns a
    summary suitable for the audit log.
    """
    summary: dict[str, dict[str, int]] = {}

    spec: list[tuple[str, str, Any]] = [
        ("patterns", "patterns/learned", render_pattern),
        ("gotchas", "gotchas", render_gotcha),
        ("investigations", "investigations", render_investigation),
        ("decisions", "decisions", render_decision),
    ]

    for key, subdir, render in spec:
        items = payload.get(key) or []
        target_dir = vault / subdir
        target_dir.mkdir(parents=True, exist_ok=True)
        existing = existing_titles(vault, subdir)
        written = 0
        skipped = 0
        for item in items:
            title = item.get("title", "").strip()
            if not title:
                skipped += 1
                continue
            slug = slugify(title)
            if slug.lower() in existing:
                skipped += 1
                log_lines.append(f"skip-dedup {subdir}/{slug}.md")
                continue
            content = render(item)
            (target_dir / f"{slug}.md").write_text(content)
            written += 1
            existing.add(slug.lower())
            log_lines.append(f"wrote {subdir}/{slug}.md")
        summary[key] = {"written": written, "skipped": skipped}

    return summary


def call_anthropic(
    api_key: str,
    model: str,
    max_tokens: int,
    transcript: str,
    modified_files: list[str],
) -> dict:
    user_content = build_user_message(transcript, modified_files)

    body = {
        "model": model,
        "max_tokens": max_tokens,
        "system": SYSTEM_PROMPT,
        "tools": [EXTRACT_TOOL],
        "tool_choice": {"type": "tool", "name": EXTRACT_TOOL["name"]},
        "messages": [{"role": "user", "content": user_content}],
    }

    req = urllib.request.Request(
        API_URL,
        data=json.dumps(body).encode("utf-8"),
        headers={
            "x-api-key": api_key,
            "anthropic-version": ANTHROPIC_VERSION,
            "content-type": "application/json",
        },
        method="POST",
    )

    try:
        with urllib.request.urlopen(req, timeout=120) as resp:
            data = json.loads(resp.read().decode("utf-8"))
    except urllib.error.HTTPError as e:
        err_body = e.read().decode("utf-8", errors="replace")[:500]
        raise SystemExit(f"anthropic-api-error {e.code}: {err_body}")
    except urllib.error.URLError as e:
        raise SystemExit(f"anthropic-network-error: {e}")

    # Find the tool_use block in the response.
    for block in data.get("content", []):
        if block.get("type") == "tool_use" and block.get("name") == EXTRACT_TOOL["name"]:
            return block.get("input") or {}
    raise SystemExit("anthropic-response-missing-tool-use")


def build_user_message(transcript: str, modified_files: list[str]) -> str:
    files_block = "\n".join(f"- {f}" for f in modified_files[:50]) or "(none)"
    if len(modified_files) > 50:
        files_block += f"\n- ... ({len(modified_files) - 50} more)"
    return (
        "Below is a Claude Code session transcript and the list of files "
        "that were modified. Extract any reusable knowledge into the "
        "structured tool call.\n\n"
        f"## Files Modified\n\n{files_block}\n\n"
        "## Transcript (most recent turns)\n\n"
        f"{transcript}"
    )


def append_audit(vault_root: Path, record: dict) -> None:
    """Append a JSONL audit record so users can see what was auto-extracted."""
    audit_dir = vault_root.parent / ".sentinel"
    audit_dir.mkdir(parents=True, exist_ok=True)
    audit_path = audit_dir / "extraction-log.jsonl"
    record["timestamp"] = dt.datetime.now(dt.timezone.utc).isoformat()
    with audit_path.open("a") as f:
        f.write(json.dumps(record) + "\n")


def main() -> int:
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("--transcript", required=True, type=Path)
    ap.add_argument("--modified-files", required=True, type=Path)
    ap.add_argument("--vault", required=True, type=Path)
    ap.add_argument("--model", default=DEFAULT_MODEL)
    ap.add_argument("--max-tokens", type=int, default=4096)
    ap.add_argument("--max-input-chars", type=int, default=60000)
    ap.add_argument("--dry-run", action="store_true")
    args = ap.parse_args()

    api_key = os.environ.get("ANTHROPIC_API_KEY")
    if not api_key and not args.dry_run:
        print("extract-knowledge: ANTHROPIC_API_KEY not set; skipping", file=sys.stderr)
        return 0

    if not args.vault.is_dir():
        print(f"extract-knowledge: vault dir {args.vault} not found; skipping", file=sys.stderr)
        return 0

    transcript = load_transcript(args.transcript, args.max_input_chars)
    if not transcript:
        print("extract-knowledge: empty/missing transcript; skipping", file=sys.stderr)
        return 0

    modified = load_modified_files(args.modified_files)

    if args.dry_run:
        print("=== DRY RUN ===")
        print(f"transcript chars: {len(transcript)}")
        print(f"modified files: {len(modified)}")
        print(f"model: {args.model}")
        print("--- system prompt ---")
        print(SYSTEM_PROMPT)
        print("--- user message preview (first 500 chars) ---")
        print(build_user_message(transcript, modified)[:500])
        return 0

    log_lines: list[str] = []
    try:
        payload = call_anthropic(
            api_key=api_key,
            model=args.model,
            max_tokens=args.max_tokens,
            transcript=transcript,
            modified_files=modified,
        )
    except SystemExit as e:
        # Log and exit cleanly so the parent hook doesn't see a hard failure.
        append_audit(
            args.vault,
            {"event": "error", "message": str(e), "model": args.model},
        )
        print(f"extract-knowledge: {e}", file=sys.stderr)
        return 0

    summary = write_items(args.vault, payload, log_lines)

    append_audit(
        args.vault,
        {
            "event": "extraction",
            "model": args.model,
            "transcript_chars": len(transcript),
            "files_modified": len(modified),
            "summary": summary,
            "actions": log_lines,
        },
    )

    total_written = sum(s["written"] for s in summary.values())
    print(
        f"extract-knowledge: {total_written} item(s) written across "
        f"{len(summary)} categories",
        file=sys.stderr,
    )
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
