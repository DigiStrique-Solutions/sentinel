#!/bin/bash
# codemap-helpers.sh — Manifest CRUD + drift detection for /sentinel-codemap.
#
# A codemap manifest at <output_dir>/.manifest.json tracks the binding between
# source files and their generated codemap entries. The two hooks
# (session-start-codemap-check, stop-codemap-refresh) and the
# /sentinel-codemap command all share this script as the source of truth.
#
# Usage:
#   bash codemap-helpers.sh <subcommand> [args...]
#
# Subcommands:
#   list-manifests <project_dir>
#       Print absolute paths of every .manifest.json under <project_dir>/vault/.
#
#   detect-drift <manifest_path>
#       Diff manifest vs. filesystem. Print classification as JSON:
#       { "modified": [...], "added": [...], "deleted": [...] }
#       - modified: source exists, mtime > generated_at, hash differs
#       - added: matches target_glob but not in manifest
#       - deleted: in manifest but source file is gone
#
#   detect-drift-files <manifest_path> <modified_files_file>
#       Same as detect-drift but only considers paths in modified_files_file.
#       Used by the Stop hook to scope refresh to session edits.
#
#   register <output_dir> <task> <target_glob> [model]
#       Build a .manifest.json by scanning <output_dir>/results/ for existing
#       codemap entries (flat-name convention: src--auth--login.py.md) and
#       computing initial source SHA256 + mtime.
#
#   status <manifest_path>
#       Print human-readable summary: total entries, stale count, missing count.
#
# Exits 0 on success or graceful no-op, non-zero on runtime error.

set -euo pipefail

# --- Internal helpers -------------------------------------------------------

# Cross-platform sha256 of a file's contents.
sha256_of() {
    local file="$1"
    if command -v sha256sum >/dev/null 2>&1; then
        sha256sum "$file" | awk '{print $1}'
    elif command -v shasum >/dev/null 2>&1; then
        shasum -a 256 "$file" | awk '{print $1}'
    else
        return 1
    fi
}

# Cross-platform file mtime as epoch seconds.
mtime_of() {
    local file="$1"
    if [[ "$OSTYPE" == "darwin"* ]]; then
        stat -f %m "$file"
    else
        stat -c %Y "$file"
    fi
}

# ISO timestamp parser → epoch seconds. Uses python3 because date(1) parsing
# differs significantly across BSD/GNU and full ISO 8601 with offset is not
# uniformly supported.
iso_to_epoch() {
    local iso="$1"
    python3 -c "
import sys, datetime as dt
try:
    s = '$iso'.rstrip('Z').replace('Z', '')
    print(int(dt.datetime.fromisoformat(s.replace('Z','')).timestamp()))
except Exception:
    print(0)
"
}

# Convert a source path to its flat-name entry filename: src--auth--login.py.md
flat_name_for() {
    local path="$1"
    echo "${path//\//--}.md"
}

# Reverse: derive the source path from a flat-name entry filename.
# WARNING: this is best-effort. If a source dir contains "--" in its name,
# the reverse mapping is ambiguous. The manifest always stores the
# authoritative mapping; this is used only by `register` for initial bootstrap.
source_from_flat() {
    local flat="$1"
    flat="${flat%.md}"
    echo "${flat//--/\/}"
}

# --- Subcommands ------------------------------------------------------------

cmd_list_manifests() {
    local project_dir="${1:?project_dir required}"
    if [ ! -d "${project_dir}/vault" ]; then
        return 0
    fi
    find "${project_dir}/vault" -maxdepth 4 -name ".manifest.json" -type f 2>/dev/null | sort
}

cmd_detect_drift() {
    local manifest="${1:?manifest path required}"
    local scope_file="${2:-}"  # optional — limit to paths in this file

    if [ ! -f "$manifest" ]; then
        echo '{"modified":[],"added":[],"deleted":[],"error":"manifest-not-found"}'
        return 0
    fi

    python3 - "$manifest" "$scope_file" <<'PY'
import sys, os, json, hashlib, datetime as dt, glob as globlib, fnmatch

manifest_path = sys.argv[1]
scope_path = sys.argv[2] if len(sys.argv) > 2 else ""

with open(manifest_path) as f:
    manifest = json.load(f)

project_root = os.path.dirname(os.path.dirname(os.path.dirname(manifest_path)))
# project_root is two levels up from .manifest.json which lives in vault/<codemap-dir>/

# Allow override via env so tests + commands can be explicit
project_root = os.environ.get("CODEMAP_PROJECT_ROOT", project_root)

target_glob = manifest.get("target_glob", "")
entries = manifest.get("entries", {})

scope = None
if scope_path and os.path.isfile(scope_path):
    with open(scope_path) as f:
        scope = {line.strip() for line in f if line.strip()}

def in_scope(path):
    if scope is None:
        return True
    if path in scope:
        return True
    abs_path = os.path.join(project_root, path)
    return abs_path in scope

def sha256_of(path):
    h = hashlib.sha256()
    with open(path, "rb") as f:
        for chunk in iter(lambda: f.read(65536), b""):
            h.update(chunk)
    return h.hexdigest()

def parse_iso(s):
    try:
        return dt.datetime.fromisoformat(s.rstrip("Z")).timestamp()
    except Exception:
        return 0

modified, deleted = [], []
for path, entry in entries.items():
    if not in_scope(path):
        continue
    abs_path = os.path.join(project_root, path) if not os.path.isabs(path) else path
    if not os.path.isfile(abs_path):
        deleted.append(path)
        continue
    # Cheap check: mtime > generated_at?
    mtime = os.path.getmtime(abs_path)
    gen_at = parse_iso(entry.get("generated_at", ""))
    if mtime <= gen_at:
        continue
    # Hash-verify (avoid spurious refresh on touch with same content)
    cur_sha = sha256_of(abs_path)
    if cur_sha != entry.get("source_sha256"):
        modified.append(path)

# Detect added files: anything matching target_glob not already in entries.
# Skip if scope was passed — added-detection is a SessionStart concern.
added = []
if scope is None and target_glob:
    # Resolve glob relative to project root
    pattern = os.path.join(project_root, target_glob) if not os.path.isabs(target_glob) else target_glob
    for abs_path in globlib.glob(pattern, recursive=True):
        if not os.path.isfile(abs_path):
            continue
        rel = os.path.relpath(abs_path, project_root)
        if rel in entries:
            continue
        # Filter common junk
        if any(seg in abs_path for seg in ("/node_modules/", "/.git/", "/__pycache__/", "/.venv/", "/dist/", "/build/")):
            continue
        added.append(rel)

print(json.dumps({"modified": sorted(modified), "added": sorted(added), "deleted": sorted(deleted)}))
PY
}

cmd_detect_drift_files() {
    cmd_detect_drift "$1" "$2"
}

cmd_register() {
    local output_dir="${1:?output_dir required}"
    local task="${2:?task required}"
    local target_glob="${3:?target_glob required}"
    local model="${4:-claude-haiku-4-5}"

    if [ ! -d "$output_dir" ]; then
        echo "register: output_dir $output_dir not found" >&2
        return 2
    fi

    # Determine the prefix for entry_path values stored in the manifest.
    # If <output_dir>/results/ exists, entries are stored as "results/<fname>".
    # Otherwise entries are stored as just "<fname>" (flat layout).
    local entry_prefix=""
    local results_dir="$output_dir"
    if [ -d "${output_dir}/results" ]; then
        results_dir="${output_dir}/results"
        entry_prefix="results/"
    fi

    local manifest_path="${output_dir}/.manifest.json"
    local project_root
    project_root="${CODEMAP_PROJECT_ROOT:-$(cd "$(dirname "$output_dir")/.." 2>/dev/null && pwd || pwd)}"

    python3 - "$results_dir" "$manifest_path" "$task" "$target_glob" "$model" "$project_root" "$entry_prefix" "$output_dir" <<'PY'
import sys, os, json, hashlib, datetime as dt, glob as globlib

results_dir, manifest_path, task, target_glob, model, project_root, entry_prefix, output_dir = sys.argv[1:9]

def sha256_of(path):
    h = hashlib.sha256()
    with open(path, "rb") as f:
        for chunk in iter(lambda: f.read(65536), b""):
            h.update(chunk)
    return h.hexdigest()

def flat_to_source(name):
    if name.endswith(".md"):
        name = name[:-3]
    return name.replace("--", "/")

now = dt.datetime.now(dt.timezone.utc).isoformat()
entries = {}
unmatched = []

for fname in sorted(os.listdir(results_dir)):
    if not fname.endswith(".md"):
        continue
    if fname == "INDEX.md":
        continue
    rel_source = flat_to_source(fname)
    abs_source = os.path.join(project_root, rel_source)
    if not os.path.isfile(abs_source):
        unmatched.append(fname)
        continue
    # entry_path is RELATIVE TO OUTPUT_DIR. Prefix with "results/" only if
    # /sentinel-batch used the nested-results layout.
    rel_entry = f"{entry_prefix}{fname}"
    entries[rel_source] = {
        "entry_path": rel_entry,
        "source_sha256": sha256_of(abs_source),
        "generated_at": now,
    }

manifest = {
    "version": 1,
    "task": task,
    "target_glob": target_glob,
    "output_dir": output_dir,
    "model": model,
    "entries": entries,
    "registered_at": now,
}

with open(manifest_path, "w") as f:
    json.dump(manifest, f, indent=2)

print(json.dumps({
    "manifest": manifest_path,
    "entries_registered": len(entries),
    "unmatched_files": unmatched,
}))
PY
}

cmd_status() {
    local manifest="${1:?manifest path required}"
    if [ ! -f "$manifest" ]; then
        echo "no manifest at $manifest" >&2
        return 1
    fi
    local drift
    drift=$(cmd_detect_drift "$manifest")
    python3 - "$manifest" "$drift" <<'PY'
import sys, json
with open(sys.argv[1]) as f:
    m = json.load(f)
d = json.loads(sys.argv[2])
total = len(m.get("entries", {}))
print(f"Codemap: {sys.argv[1]}")
print(f"  Task:    {m.get('task','?')[:80]}")
print(f"  Glob:    {m.get('target_glob','?')}")
print(f"  Model:   {m.get('model','?')}")
print(f"  Entries: {total}")
print(f"  Drift:   {len(d.get('modified',[]))} modified, {len(d.get('added',[]))} added, {len(d.get('deleted',[]))} deleted")
if d.get("modified"):
    print("  Modified:")
    for p in d["modified"][:10]:
        print(f"    - {p}")
    if len(d["modified"]) > 10:
        print(f"    ... and {len(d['modified']) - 10} more")
if d.get("added"):
    print("  Added:")
    for p in d["added"][:10]:
        print(f"    - {p}")
if d.get("deleted"):
    print("  Deleted:")
    for p in d["deleted"][:10]:
        print(f"    - {p}")
PY
}

# --- Dispatch ---------------------------------------------------------------

SUB="${1:-}"
shift || true

case "$SUB" in
    list-manifests)      cmd_list_manifests "$@" ;;
    detect-drift)        cmd_detect_drift "$@" ;;
    detect-drift-files)  cmd_detect_drift_files "$@" ;;
    register)            cmd_register "$@" ;;
    status)              cmd_status "$@" ;;
    "")
        echo "codemap-helpers.sh: subcommand required. Run with -h for usage." >&2
        exit 2
        ;;
    -h|--help)
        sed -n '2,40p' "$0"
        exit 0
        ;;
    *)
        echo "codemap-helpers.sh: unknown subcommand: $SUB" >&2
        exit 2
        ;;
esac
