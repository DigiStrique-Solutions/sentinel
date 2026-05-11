#!/usr/bin/env python3
"""
Background codemap refresh worker for Sentinel.

Reads a codemap manifest, detects drift against the filesystem, and for any
modified-or-added files calls the Anthropic Messages API to regenerate the
corresponding codemap entry. Deletes entries whose source file is gone.

Spawned (detached, background) by:
  - hooks/optional/session-start-codemap-check.sh — on session start, full
    drift scan against the filesystem.
  - hooks/optional/stop-codemap-refresh.sh — on session end, scoped to files
    Claude edited in the session.

Can also be invoked directly by /sentinel-codemap refresh.

Inputs:
  --manifest    Path to <output_dir>/.manifest.json (required)
  --project-root  Repo root (default: derived as 3 levels up from manifest)
  --paths-file  Optional: limit drift detection to paths in this file
                (one per line; either absolute or relative to project root)
  --model       Override model from manifest (default: manifest's model)
  --max-input-chars  Cap on per-file content sent to the API (default: 40000)
  --dry-run     Detect drift and print plan, don't call API or write files

Exit codes:
  0   success or graceful no-op (missing API key, manifest, drift, etc.)
  >0  unexpected error

Audit log: appends per-run JSONL record to .sentinel/codemap-refresh.jsonl.
"""
from __future__ import annotations

import argparse
import datetime as dt
import hashlib
import json
import os
import subprocess
import sys
import urllib.error
import urllib.request
from pathlib import Path

API_URL = "https://api.anthropic.com/v1/messages"
ANTHROPIC_VERSION = "2023-06-01"


def sha256_of(path: Path) -> str:
    h = hashlib.sha256()
    with path.open("rb") as f:
        for chunk in iter(lambda: f.read(65536), b""):
            h.update(chunk)
    return h.hexdigest()


def detect_drift(
    manifest: dict,
    project_root: Path,
    scope_paths: set[str] | None,
) -> dict:
    """Return {modified, added, deleted} lists of source paths (relative)."""
    helpers = Path(__file__).parent / "codemap-helpers.sh"
    manifest_path = manifest["__path__"]
    scope_arg = manifest.get("__scope_file__", "")
    env = os.environ.copy()
    env["CODEMAP_PROJECT_ROOT"] = str(project_root)
    result = subprocess.run(
        ["bash", str(helpers), "detect-drift", str(manifest_path), scope_arg],
        capture_output=True,
        text=True,
        env=env,
    )
    if result.returncode != 0:
        raise SystemExit(f"codemap-helpers detect-drift failed: {result.stderr}")
    return json.loads(result.stdout)


def call_anthropic(
    api_key: str,
    model: str,
    system_prompt: str,
    user_content: str,
    max_tokens: int = 2048,
) -> str:
    body = {
        "model": model,
        "max_tokens": max_tokens,
        "system": system_prompt,
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
        err = e.read().decode("utf-8", errors="replace")[:500]
        raise SystemExit(f"anthropic-api-error {e.code}: {err}")
    except urllib.error.URLError as e:
        raise SystemExit(f"anthropic-network-error: {e}")

    # Concatenate all text blocks from the response
    texts = []
    for block in data.get("content", []):
        if block.get("type") == "text":
            texts.append(block.get("text", ""))
    out = "\n".join(t for t in texts if t).strip()
    if not out:
        raise SystemExit("anthropic-response-empty")
    return out


def build_system_prompt(task: str) -> str:
    return (
        f"You are generating one entry for a codemap. The user task is: {task}\n\n"
        "Output ONLY the markdown for this single file's entry. Do not wrap in "
        "code fences. Do not add preamble. Start with an H1 heading containing "
        "the file path. Include sections for purpose, exports/API surface, and "
        "key dependencies. Be concise — aim for 200-400 words. If the file is "
        "trivial (empty, a re-export, a config), say so and stop."
    )


def build_user_message(source_path: str, content: str, max_chars: int) -> str:
    if len(content) > max_chars:
        content = content[:max_chars] + f"\n\n[truncated — original was {len(content)} chars]"
    return (
        f"## File: {source_path}\n\n"
        f"```\n{content}\n```\n\n"
        "Generate the codemap entry for this file."
    )


def regenerate_one(
    api_key: str,
    model: str,
    task: str,
    output_dir: Path,
    project_root: Path,
    rel_source: str,
    entry_path: str,
    max_input_chars: int,
) -> tuple[bool, str]:
    """Return (success, sha_or_error)."""
    abs_source = project_root / rel_source
    if not abs_source.is_file():
        return (False, "source-missing")
    try:
        content = abs_source.read_text(errors="replace")
    except OSError as e:
        return (False, f"read-error: {e}")

    system = build_system_prompt(task)
    user_msg = build_user_message(rel_source, content, max_input_chars)
    try:
        body = call_anthropic(api_key, model, system, user_msg)
    except SystemExit as e:
        return (False, str(e))

    target = output_dir / entry_path
    target.parent.mkdir(parents=True, exist_ok=True)
    target.write_text(body + "\n")
    return (True, sha256_of(abs_source))


def append_audit(project_root: Path, record: dict) -> None:
    audit_dir = project_root / ".sentinel"
    audit_dir.mkdir(parents=True, exist_ok=True)
    record["timestamp"] = dt.datetime.now(dt.timezone.utc).isoformat()
    with (audit_dir / "codemap-refresh.jsonl").open("a") as f:
        f.write(json.dumps(record) + "\n")


def main() -> int:
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("--manifest", required=True, type=Path)
    ap.add_argument("--project-root", type=Path, default=None)
    ap.add_argument("--paths-file", type=Path, default=None)
    ap.add_argument("--model", default=None)
    ap.add_argument("--max-input-chars", type=int, default=40000)
    ap.add_argument("--dry-run", action="store_true")
    args = ap.parse_args()

    if not args.manifest.is_file():
        print(f"refresh-codemap: manifest {args.manifest} not found; skipping", file=sys.stderr)
        return 0

    manifest = json.loads(args.manifest.read_text())
    manifest["__path__"] = str(args.manifest)
    if args.paths_file and args.paths_file.is_file():
        manifest["__scope_file__"] = str(args.paths_file)
    else:
        manifest["__scope_file__"] = ""

    # Derive project root. Manifest at <project>/vault/<dir>/.manifest.json
    # means project root is .manifest.json's parent.parent.parent.
    project_root = args.project_root
    if project_root is None:
        project_root = args.manifest.parent.parent.parent
    project_root = project_root.resolve()

    output_dir = args.manifest.parent  # .manifest.json lives at output_dir/.manifest.json

    drift = detect_drift(manifest, project_root, scope_paths=None)
    modified = drift.get("modified", [])
    added = drift.get("added", [])
    deleted = drift.get("deleted", [])

    if not (modified or added or deleted):
        print("refresh-codemap: no drift; skipping", file=sys.stderr)
        return 0

    if args.dry_run:
        print(json.dumps({
            "dry_run": True,
            "modified": modified,
            "added": added,
            "deleted": deleted,
        }, indent=2))
        return 0

    api_key = os.environ.get("ANTHROPIC_API_KEY")
    if not api_key:
        print("refresh-codemap: ANTHROPIC_API_KEY not set; skipping", file=sys.stderr)
        append_audit(project_root, {
            "event": "skipped-no-api-key",
            "manifest": str(args.manifest),
            "drift": {"modified": len(modified), "added": len(added), "deleted": len(deleted)},
        })
        return 0

    model = args.model or manifest.get("model") or "claude-haiku-4-5"
    task = manifest.get("task", "")

    # Build entries map so we know each file's entry_path (or generate one for adds).
    entries = manifest.get("entries", {})

    refreshed: list[str] = []
    failures: list[dict] = []

    # 1. Process modifications + additions (regenerate entry)
    # New entries are written into the same subdir as existing entries (preserving
    # whether /sentinel-batch used a flat layout or nested results/).
    existing_subdir = ""
    for e in entries.values():
        ep = e.get("entry_path", "")
        if "/" in ep:
            existing_subdir = ep.rsplit("/", 1)[0]
            break

    for rel_source in modified + added:
        if rel_source in entries:
            entry_path = entries[rel_source]["entry_path"]
        else:
            flat = rel_source.replace("/", "--") + ".md"
            entry_path = f"{existing_subdir}/{flat}" if existing_subdir else flat
        ok, info = regenerate_one(
            api_key=api_key,
            model=model,
            task=task,
            output_dir=output_dir,
            project_root=project_root,
            rel_source=rel_source,
            entry_path=entry_path,
            max_input_chars=args.max_input_chars,
        )
        if ok:
            entries[rel_source] = {
                "entry_path": entry_path,
                "source_sha256": info,
                "generated_at": dt.datetime.now(dt.timezone.utc).isoformat(),
            }
            refreshed.append(rel_source)
        else:
            failures.append({"path": rel_source, "error": info})

    # 2. Process deletions
    for rel_source in deleted:
        entry = entries.pop(rel_source, None)
        if entry:
            entry_file = output_dir / entry["entry_path"]
            try:
                entry_file.unlink(missing_ok=True)
            except OSError:
                pass

    # 3. Write updated manifest atomically
    manifest_out = {k: v for k, v in manifest.items() if not k.startswith("__")}
    manifest_out["entries"] = entries
    manifest_out["last_refreshed_at"] = dt.datetime.now(dt.timezone.utc).isoformat()
    tmp = args.manifest.with_suffix(".json.tmp")
    tmp.write_text(json.dumps(manifest_out, indent=2))
    tmp.replace(args.manifest)

    append_audit(project_root, {
        "event": "refresh",
        "manifest": str(args.manifest),
        "model": model,
        "refreshed": refreshed,
        "deleted": deleted,
        "failures": failures,
    })

    print(
        f"refresh-codemap: {len(refreshed)} regenerated, "
        f"{len(deleted)} deleted, {len(failures)} failed",
        file=sys.stderr,
    )
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
