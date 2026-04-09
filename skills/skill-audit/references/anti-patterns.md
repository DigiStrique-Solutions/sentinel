# Skill Anti-Patterns

## Table of Contents

- [Description anti-patterns](#description-anti-patterns)
- [Body anti-patterns](#body-anti-patterns)
- [Structural anti-patterns](#structural-anti-patterns)
- [Triggering anti-patterns](#triggering-anti-patterns)
- [Process anti-patterns](#process-anti-patterns)
- [Quick checklist](#quick-self-review-checklist)

The complete catalog of anti-patterns the griller looks for, with BAD and GOOD examples for each. Use this when running the griller inline (no subagent), or as a reference when fixing issues the griller surfaces.

---

## Description anti-patterns

### Vague descriptions

**BAD:**
```yaml
description: Helps with documents.
```

**GOOD:**
```yaml
description: Extract text and tables from PDF files, fill forms, merge documents. Use when working with PDF files or when the user mentions PDFs, forms, or document extraction.
```

The good version names the actual capabilities AND signals when to fire.

---

### First/second person

**BAD:**
```yaml
description: I can help you analyze Excel files. You can use this to extract data or create charts.
```

**GOOD:**
```yaml
description: Analyze Excel spreadsheets, create pivot tables, generate charts. Use when analyzing Excel files, spreadsheets, tabular data, or .xlsx files.
```

Skill descriptions are not conversational invitations — they're third-person capability summaries.

---

### Missing the WHEN

**BAD:**
```yaml
description: Generates Python unit tests using pytest conventions.
```

**GOOD:**
```yaml
description: Generates Python unit tests using pytest conventions. Use when the user asks for tests, mentions test coverage, has untested code, or is working in a Python project with a tests/ directory.
```

The good version gives Claude explicit triggers to match against.

---

### Buried trigger keywords

**BAD:**
```yaml
description: A comprehensive utility for working with various data formats and transformations, originally developed by the data team in Q3 2024 to address several inefficiencies in the existing workflow. Use when working with CSV files.
```

The "Use when CSV files" trigger is past the 250-char truncation point — Claude Code may not see it.

**GOOD:**
```yaml
description: Convert, filter, and transform CSV files. Use when working with CSV data, when the user mentions spreadsheets, or when processing tabular files.
```

Front-load the triggers.

---

### Trigger overlap with built-in tools

**BAD:**
```yaml
description: Reads files from the filesystem. Use when the user wants to view a file.
```

This will never trigger — Claude has the Read tool built in and will use it directly.

**GOOD:**
Either don't ship the skill (built-ins are better), or scope it to a specific value-add:
```yaml
description: Reads and parses Apache log files, surfacing error patterns and unusual request volumes. Use when the user wants to analyze access.log, error.log, or other web server logs.
```

---

## Body anti-patterns

### ALL-CAPS / "CRITICAL: YOU MUST"

**BAD:**
```
CRITICAL: You MUST ALWAYS read the file before answering. NEVER skip this step.
```

**GOOD:**
```
Read the relevant file before answering. The user often references specific files by name, and answering without reading them produces incorrect responses.
```

Modern models (Claude 4.6, GPT-5) overtrigger on emphatic language. Calm declarative instructions with a brief reason work better.

---

### Negative-only instructions

**BAD:**
```
- Don't use sed
- Don't use awk
- Don't use cat for reading files
```

**GOOD:**
```
- Use Edit instead of sed for in-place modifications
- Use Grep instead of awk for content searches
- Use Read instead of cat to view files (Read shows line numbers and integrates with the harness)
```

Negative instructions force the model to infer what to do instead. Pair with positive alternatives.

---

### Vague language

**BAD:**
```
Be helpful when responding to user queries. Use best judgment when handling edge cases. Be appropriate and professional.
```

**GOOD:**
```
Answer the user's question directly in 1-3 sentences. For multi-step questions, expand to a numbered list. Match the user's level of formality.
```

Apply the new-colleague test: would a new hire know what to do from this?

---

### Missing the why

**BAD:**
```
Always commit changes in batches of fewer than 10 files.
```

**GOOD:**
```
Commit changes in batches of fewer than 10 files. The CI runs tests against each batch, and batches of 10+ files routinely time out, causing flaky failures that block the team.
```

The good version means the model can apply the rule to unanticipated cases (e.g., it knows to make even smaller batches when files are large).

---

### Time-sensitive language

**BAD:**
```
As of August 2025, the API requires v2 authentication tokens. Before that, it accepted v1.
```

**GOOD:**
```
The API requires v2 authentication tokens.

<details>
<summary>Legacy: v1 token support (deprecated)</summary>
Before the v2 migration, the API accepted v1 tokens. v1 is now rejected.
</details>
```

Time-sensitive phrases age poorly. Use collapsed `<details>` blocks for legacy content so Claude doesn't have to parse "what year is it now."

---

### Too many alternatives without a default

**BAD:**
```
You can use pypdf or pdfplumber or PyMuPDF or pdfminer or pdfrw to extract text.
```

**GOOD:**
```
Use pdfplumber to extract text. If pdfplumber doesn't preserve layout (e.g., for multi-column documents), fall back to PyMuPDF.
```

Pick a default with an escape hatch. Five alternatives forces the model to choose for no reason.

---

### Inconsistent terminology

**BAD:** SKILL.md uses "field," "input," "element," and "control" interchangeably for the same concept.

**GOOD:** Pick one word and never switch.

---

### Voodoo constants

**BAD:**
```python
# In a bundled script
TIMEOUT = 47
MAX_RETRIES = 3
```

**GOOD:**
```python
# 47s = 5s less than the upstream gateway's 52s timeout, leaving headroom
# for the response to come back before the gateway gives up.
TIMEOUT = 47
# 3 retries with exponential backoff covers the 99th percentile of
# transient failures observed in the last 90 days.
MAX_RETRIES = 3
```

If you don't know the right value, how will Claude?

---

## Structural anti-patterns

### Deeply nested references

**BAD:**
```
SKILL.md → references/advanced.md → references/details/api.md → references/details/api/auth.md
```

Claude may partial-read files (`head -100`) when chasing nested links and miss content.

**GOOD:**
```
SKILL.md → references/advanced.md
SKILL.md → references/api.md
SKILL.md → references/auth.md
```

Keep references one level deep. Link directly from SKILL.md to every reference.

---

### Long reference files without TOC

**BAD:** A 200-line `references/api.md` with no headers.

**GOOD:** Same file with a `## Table of Contents` at the top, listing the major sections so partial reads still surface what's available.

---

### Orphan bundled files

**BAD:** `scripts/helper.py` exists in the skill directory but SKILL.md never mentions it. Claude will never find it.

**GOOD:** Either reference the file from SKILL.md ("Run `python scripts/helper.py`...") or delete it.

---

### Reading scripts instead of running them

**BAD:**
```
For form analysis, see `scripts/analyze_form.py` for the algorithm.
```

This pulls the script source into context, defeating the token-saving purpose of bundled scripts.

**GOOD:**
```
For form analysis, run `python scripts/analyze_form.py <input.pdf>`. The script extracts field names and types and prints them as JSON.
```

Treat scripts as black boxes. Claude runs them; their output enters context, their source does not.

---

## Triggering anti-patterns

### Under-triggering

The skill exists but never fires.

**Causes:**
- Vague description
- Trigger keywords past the 250-char truncation
- Description too narrow (matches only one specific phrasing)
- Skill targets tasks too simple to justify a skill (Claude uses built-ins)

**Fix:** Make the description pushier and more specific. Add explicit "Use this skill whenever the user mentions X, Y, or Z" language.

---

### Over-triggering

The skill fires on requests it shouldn't handle.

**Causes:**
- Description too broad
- Description matches keywords in unrelated domains
- Skill should be user-only, not auto-invoked

**Fix:** Make the description more specific. For skills that should only fire on explicit user request, set `disable-model-invocation: true` in frontmatter.

---

### Skills competing with built-in tools

If the skill duplicates a built-in (Read, Grep, Glob, Edit, Write, Bash), Claude will use the built-in regardless of how good the description is. The skill is dead code.

**Fix:** Either delete the skill or scope it to a specific value-add the built-in doesn't provide (parsing, multi-step workflows, deterministic scripts, reference material).

---

## Process anti-patterns

### Writing extensive docs before evals

Skill-creator's iteration loop is built around eval-driven development. Writing 2000 lines of SKILL.md before running it on a single test case is the wrong order.

**Fix:** Write a minimal draft, run it on 3 realistic prompts, then iterate.

---

### Iterating without baselines

If you change the skill and the new version produces different output, you don't know if it's better unless you compare against the baseline (no skill, or previous version).

**Fix:** Always run with-skill AND baseline in parallel for every iteration.

---

### Forcing quantitative metrics on subjective skills

Some skills produce subjective outputs (writing style, design quality). Forcing assertions on them creates false signal.

**Fix:** Use qualitative review via the eval viewer for subjective skills. Reserve quantitative assertions for objective outputs (file transforms, data extraction, code generation).

---

### Overfitting to test cases

The skill works perfectly on the 3 test cases but fails on everything else.

**Fix:** Generalize from feedback. If a stubborn issue won't go away, try a different metaphor or approach instead of fiddly test-specific patches. Periodically expand the test set.

---

## Quick self-review checklist

After drafting a skill, scan for:

- [ ] Description is third-person, has WHAT and WHEN, is "pushy" enough
- [ ] Trigger keywords are front-loaded (in first 250 chars)
- [ ] SKILL.md is under 500 lines
- [ ] No ALL-CAPS / "CRITICAL" bombing
- [ ] No negative-only instructions
- [ ] No vague language ("be helpful", "use best judgment")
- [ ] Every non-obvious instruction has a brief reason
- [ ] No time-sensitive language outside of `<details>` blocks
- [ ] Single chosen default for any list of alternatives
- [ ] Consistent terminology throughout
- [ ] No voodoo constants in bundled scripts
- [ ] References are one level deep (no chains)
- [ ] Long reference files have TOCs
- [ ] No orphan bundled files
- [ ] Scripts are treated as black boxes (run, not read)
- [ ] Skill provides value above built-in tools
- [ ] No contradictions between sections
- [ ] Stop conditions and escape hatches are explicit
