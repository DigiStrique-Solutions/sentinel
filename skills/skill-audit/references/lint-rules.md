# Lint Rules

## Table of Contents

- [Frontmatter (FM)](#frontmatter-fm)
- [Body (BD)](#body-bd)
- [Structure (ST)](#structure-st)
- [Reference files (RF)](#reference-files-rf)
- [Skill-level (SK)](#skill-level-sk)
- [Tuning false positives](#tuning-false-positives)

Complete catalog of what `lint_skill.py` checks and the rationale for each rule. Rules are grouped by category and identified by a stable code (e.g., `FM001`).

---

## Frontmatter (FM)

### FM000 — Missing or malformed YAML frontmatter
**Severity:** ERROR
**Why:** SKILL.md requires YAML frontmatter wrapped in `---` markers at the top of the file. Without it, Claude Code cannot register the skill.

### FM001 — Missing required `name` field
**Severity:** ERROR
**Why:** `name` is required by every Claude Code surface. Without it, the skill cannot be invoked or referenced.

### FM002 — `name` exceeds 64 characters
**Severity:** ERROR
**Why:** The 64-character limit is enforced by Claude Code's plugin system.

### FM003 — `name` does not match `^[a-z][a-z0-9-]{0,63}$`
**Severity:** ERROR
**Why:** Names must be lowercase letters, digits, and hyphens only, starting with a letter. Underscores, uppercase, and other characters are rejected.

### FM004 — `name` contains a reserved word
**Severity:** ERROR
**Why:** Names containing "anthropic" or "claude" are reserved by Anthropic and may collide with built-in skills.

### FM010 — Missing required `description` field
**Severity:** ERROR
**Why:** The description is the **only thing Claude sees during selection**. Without it, the skill is undiscoverable.

### FM011 — `description` exceeds 1024 characters
**Severity:** ERROR
**Why:** 1024 chars is the hard limit. Claude Code further truncates to ~250 chars in the listing.

### FM012 — `description` contains first-person language
**Severity:** ERROR
**Why:** Skill descriptions must be third person ("Processes Excel files...") not first person ("I can help you..."). First-person breaks discovery — the model selection logic expects descriptive prose, not conversational invitations.

### FM013 — `description` contains second-person language
**Severity:** WARN
**Why:** Same as FM012 but for second-person phrasings. Slightly less harmful but still suboptimal.

### FM014 — `description` is missing a "when" trigger phrase
**Severity:** WARN
**Why:** A description needs both WHAT (what the skill does) and WHEN (when to use it). Without a "when" signal — phrases like "use when," "when the user," "whenever" — Claude lacks an explicit trigger.

### FM015 — `description` opens vaguely
**Severity:** WARN
**Why:** Openers like "Helps with...", "Useful for...", and "Does stuff..." are too generic to win selection against more specific skills.

### FM016 — Trigger keywords appear after the 250-char truncation point
**Severity:** WARN
**Why:** Claude Code truncates descriptions to ~250 chars in the skill listing. Trigger keywords buried after that point may not be visible during selection.

---

## Body (BD)

### BD001 — SKILL.md exceeds line count
**Severity:** WARN at 400 lines, ERROR at 500 lines
**Why:** The repeated guidance from Anthropic's docs is to keep SKILL.md under 500 lines. Above that, performance degrades and the file should be split into `references/`.

### BD002 — First-person references in body
**Severity:** WARN
**Why:** Body should be in third-person imperative form ("Extract the form fields...") not first/second person ("I will extract..." or "You should extract...").

### BD003 — Excessive ALL-CAPS words
**Severity:** WARN at >5 ALL-CAPS words
**Why:** Modern models (Claude 4.6, GPT-5) overtrigger on emphatic ALL-CAPS language. Tools that under-triggered on older models now trigger appropriately, so emphatic instructions cause overuse. The linter excludes common acronyms (JSON, API, URL, etc.).

### BD004 — Excessive rigid directives
**Severity:** WARN at >8 occurrences of MUST/NEVER/ALWAYS/CRITICAL/REQUIRED combined
**Why:** Heavy use of rigid directives is a yellow flag. Per Anthropic's skill-creator: "If you find yourself writing ALWAYS or NEVER in all caps, or using super rigid structures, that's a yellow flag — if possible, reframe and explain the reasoning."

### BD005 — Time-sensitive language
**Severity:** WARN
**Why:** Phrases like "as of August 2025" or "before January 2026" age poorly and become wrong as time passes. Wrap legacy guidance in collapsed `<details>` blocks instead.

### BD006 — Windows-style backslash paths
**Severity:** WARN
**Why:** All paths in SKILL.md should use forward slashes. Backslashes break cross-platform behavior and confuse Claude. The check skips lines inside fenced code blocks.

---

## Structure (ST)

### ST001 — Link points outside skill directory
**Severity:** WARN
**Why:** Skills should be self-contained. Links pointing to files outside the skill directory create hidden dependencies and may break when the skill is packaged or installed elsewhere.

### ST002 — Broken link to local file
**Severity:** ERROR
**Why:** A markdown link in SKILL.md points to a local file that doesn't exist. The link will fail when Claude tries to read it.

### ST003 — File in scripts/, references/, assets/, or agents/ not referenced from SKILL.md
**Severity:** WARN
**Why:** Bundled files that SKILL.md never mentions are orphans — Claude won't find them because the SKILL.md is the entrypoint. Either reference the file or remove it.

### ST004 — Reference file links to another reference file
**Severity:** WARN
**Why:** Anthropic's docs explicitly warn against deeply nested references. Claude may partial-read files when chasing nested links. Keep references one level deep from SKILL.md — link directly from the entrypoint.

---

## Reference files (RF)

### RF001 — Long reference file has no table of contents
**Severity:** WARN at 100+ lines
**Why:** For reference files >100 lines, put a table of contents at the top so partial reads still surface what's available. Look for `## Table of Contents`, `## TOC`, or `## Contents` near the top of the file.

---

## Skill-level (SK)

### SK001 — Skill directory does not exist
**Severity:** ERROR
**Why:** Self-explanatory. The path passed to the linter must be a real directory.

### SK002 — Missing SKILL.md
**Severity:** ERROR
**Why:** Every skill must have a `SKILL.md` (exact spelling) at the root of the skill directory. This is the entrypoint Claude Code looks for.

### SK003 — Cannot read SKILL.md
**Severity:** ERROR
**Why:** Permissions issue or filesystem error. Investigate the underlying error message.

---

## Tuning false positives

A few rules will occasionally flag intentional content:

**BD003 (ALL-CAPS)** flags BAD examples in anti-pattern documentation. If your SKILL.md teaches about ALL-CAPS as an anti-pattern by quoting it inline (`"CRITICAL: YOU MUST"`), the linter will flag it. Fix by moving the quoted example into a fenced code block — the linter strips fenced blocks before counting ALL-CAPS words.

**BD002 (first-person)** flags first-person language anywhere in the body. If you must illustrate a first-person example, escape it (e.g., `"I" + " can help"`) or move it inside a code block.

**FM015 (vague opener)** can be over-eager. If your skill genuinely starts with "Useful for..." in a clearly-bounded context, the WARN can be suppressed by rewording — e.g., "Audits Claude Code skills..." instead of "Useful for auditing skills...".

**ST003 (orphan files)** uses a heuristic: it considers a file "referenced" if its name or relative path appears anywhere in SKILL.md. Files referenced only via shell variables (`${CLAUDE_PLUGIN_ROOT}/scripts/foo.py`) may need a literal mention as well.

The linter's job is to surface candidates. Always review WARN findings — some are genuine, some are tradeoffs.
