---
name: sentinel-skill-audit
description: Audit a Claude Code skill for quality issues — runs a deterministic linter for the obvious problems and an adversarial griller for the design ones. Use this skill whenever the user has just authored or edited a SKILL.md, wants to review an existing skill before shipping it, asks to "audit", "lint", "review", "grill", or "stress test" a skill, or mentions checking a skill for anti-patterns. Make sure to use this skill any time skill quality is in question, even if the user doesn't explicitly say "audit" — for example when they say "is this skill good", "what's wrong with this SKILL.md", or "review my skill before I publish it". Complements `skill-creator`, which handles authoring and behavioral evals; `skill-audit` handles static review and adversarial design review.
origin: sentinel
---

# Skill Audit

A focused review tool for Claude Code skills. Catches the issues that `skill-creator`'s outcome-based eval loop can't see — things that live in the SKILL.md document itself rather than in its outputs.

## What this skill is (and isn't)

**This skill IS** a static + adversarial review of a SKILL.md and its bundled files. It looks at the document, not the outputs.

**This skill is NOT** an authoring tool (use `anthropic-skills:skill-creator`), an eval runner (use `skill-creator`'s iteration loop), or a description optimizer (use `skill-creator`'s `run_loop.py`). It composes with all of those — run skill-audit between drafting and eval-ing, or as a periodic check on existing skills.

## When to run this

- **After drafting a new skill**, before running expensive evals
- **After editing an existing skill** to confirm the change didn't introduce new issues
- **Before publishing** a skill to a marketplace or sharing it with a team
- **Periodically** as maintenance on installed skills (skills rot as Claude Code evolves)
- **When debugging** a skill that "isn't triggering" or "behaves inconsistently"

## The three layers

skill-audit runs three layers of review, ordered cheap-to-expensive:

| Layer | Tool | What it catches | Cost |
|---|---|---|---|
| 1. Linter | `scripts/lint_skill.py` | Frontmatter violations, line counts, broken links, orphan files, ALL-CAPS, time-sensitive language, path conventions | Free, fast |
| 2. Griller | `agents/griller.md` (or inline) | Vague language, contradictions, missing whys, description quality, progressive disclosure, anti-patterns | One LLM pass |
| 3. (External) Eval loop | `skill-creator`'s iteration workflow | Actual behavior on real prompts | Many LLM calls |

skill-audit covers layers 1 and 2. Layer 3 belongs to skill-creator.

## The workflow

### Phase 1: Locate the skill

Confirm the path to the skill being audited. If the user gave you a path, use that. If not, ask. Common locations:

- Personal skills: `~/.claude/skills/<name>/`
- Project skills: `.claude/skills/<name>/`
- Plugin skills: `<plugin>/skills/<name>/`
- Sentinel-bundled skills: `sentinel/skills/<name>/`

The skill must contain a `SKILL.md` file. If not, that's the first issue to report.

### Phase 2: Run the linter

Execute the bundled linter:

```bash
python "${CLAUDE_PLUGIN_ROOT:-$HOME/.claude/plugins/marketplaces/strique-marketplace/plugins/sentinel}/skills/skill-audit/scripts/lint_skill.py" <path-to-skill>
```

Or, more portably from inside this skill's loaded context, use the path relative to wherever the skill itself is installed. The linter prints findings to stdout in this format:

```
SKILL.md:12  ERROR    Description contains first-person language (matches /\bI can\b/)
SKILL.md:1   WARN     SKILL.md is 478 lines (target <500)
references/api.md  WARN  No table of contents (file is 142 lines)
```

The linter exits non-zero if any ERROR-level finding exists.

Read `references/lint-rules.md` for the complete catalog of what the linter checks and why.

### Phase 3: Run the griller

After the linter is clean (or after surfacing its findings to the user), run the adversarial griller. Two modes:

**Sub-agent mode** (preferred when sub-agents are available): spawn the griller sub-agent with the SKILL.md content as input. Its instructions are in `agents/griller.md`. It returns a numbered list of issues with severity and suggested fixes.

**Inline mode** (when sub-agents aren't available): read `agents/griller.md` yourself and walk through its lenses against the SKILL.md, producing the same numbered issue list.

### Phase 4: Present findings

Combine the linter and griller outputs into a single report ordered by severity:

```
# Skill audit: <skill-name>

## Blockers (N)
1. ...
2. ...

## Major issues (N)
1. ...
2. ...

## Minor issues (N)
1. ...
2. ...

## Summary
- Top 3 fixes to apply first
- Patterns observed (e.g., "consistently relies on negative instructions")
- What's working well (briefly)
```

### Phase 5: Apply fixes (optional, with user consent)

If the user wants you to apply fixes directly, do so — but **always confirm before editing the SKILL.md**, since the user may have intentional reasons for some patterns the audit flagged. Apply the obvious fixes (broken links, ALL-CAPS, frontmatter issues) freely; discuss the design-level fixes (description rewording, structural changes) before applying.

## Auditing the skill-audit skill

This skill should be self-applicable. If you're auditing skill-audit itself, run the linter and griller on `<sentinel>/skills/skill-audit/SKILL.md`. If the audit produces findings, fix them — the meta-loop is the test of whether the skill is internally consistent.

## Composing with skill-creator

skill-audit is designed to slot into `skill-creator`'s authoring loop:

1. **`skill-creator`**: capture intent, draft SKILL.md, write test cases
2. **`skill-audit`**: lint + grill (catches obvious + design issues before any eval runs)
3. **`skill-creator`**: run with-skill vs baseline evals, review outputs
4. **`skill-audit`**: re-run after each iteration to catch regressions
5. **`skill-creator`**: package and ship

The two skills don't share state — skill-audit just reads SKILL.md files. You can run it standalone on any skill, including ones you didn't author.

## Reference files

- `references/lint-rules.md` — complete catalog of deterministic checks the linter performs, with rationale
- `references/anti-patterns.md` — the full anti-pattern catalog the griller uses, with BAD/GOOD examples

## Subagents

- `agents/griller.md` — adversarial reviewer that reads a SKILL.md and reports design-level issues across nine review lenses

## Scripts

- `scripts/lint_skill.py` — deterministic linter, takes a skill directory path, prints findings, exits non-zero on errors
