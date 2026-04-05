---
name: sentinel-context
description: Audit all context sources — CLAUDE.md, rules, MCP servers, plugins, hooks, vault — with token estimates and optimization recommendations.
---

# Context Audit Command

Measure the token footprint of every context source in the current project. Report sizes, identify waste, and recommend optimizations.

Use the `wc -c` command to measure file sizes. Estimate tokens as `chars / 3.5` (conservative heuristic).

## 1. CLAUDE.md Analysis

Read the project's `CLAUDE.md` file.

```
CLAUDE.md Context
Total size:          <chars> chars (~<tokens> tokens)
@ references:        <count> (each eagerly loads the target file)
Backtick references: <count> (lazy — loaded on demand)
```

For each `@` reference found, measure the target file's size and report:

```
Eager Loads (@ references)
File                               Size       Tokens
@vault/quality/anti-patterns.md    4,200 ch   ~1,200 tk
@vault/quality/test-standards.md   3,800 ch   ~1,086 tk
@vault/workflows/bug-fix.md        2,100 ch   ~600 tk
────────────────────────────────────────────────
Total eager load:                  10,100 ch  ~2,886 tk
```

**Flag:** If total eager load exceeds 5,000 tokens, recommend converting `@` references to backtick paths for progressive disclosure.

## 2. Rules Files

Count and measure all rules files:

```bash
# Global rules
ls ~/.claude/rules/**/*.md 2>/dev/null

# Project rules
ls .claude/rules/**/*.md 2>/dev/null
```

Report:

```
Rules Context
Global (~/.claude/rules/):   <count> files, ~<tokens> tokens
Project (.claude/rules/):    <count> files, ~<tokens> tokens
Total rules:                 ~<tokens> tokens
```

## 3. MCP Servers

Read `.mcp.json` (project root) and `~/.claude/mcp.json` (global) if they exist.

For each MCP server:
- Count the number of deferred tool names it contributes (check the system reminders for `mcp__<server>__*` patterns)
- Estimate token cost: each deferred tool name costs ~3-5 tokens for the name alone

```
MCP Servers
Server                  Tools    Est. Tokens
Claude_Preview          15       ~60 tk
Figma                   10       ~40 tk
plugin_playwright       25       ~100 tk
Claude_in_Chrome        18       ~72 tk
────────────────────────────────────────
Total MCP overhead:     68       ~272 tk
```

**Note:** Deferred tools only load their full schema when invoked via ToolSearch, but their names are always present in context. Many tools may never be used in a typical session.

## 4. Installed Plugins

Check `~/.claude/plugins/` for installed plugins. For each:
- Count commands, skills, agents, rules, hooks
- Estimate the session-start context each contributes

```
Plugins
Plugin              Commands  Skills  Agents  Hooks  Est. Session Context
sentinel            10        6       8       19     ~2,000 tk (budgeted)
superpowers          5        12      0       0      ~800 tk
────────────────────────────────────────────────────────────────────
Total plugin overhead:                               ~2,800 tk
```

## 5. Sentinel Hook Output

Estimate the token cost of Sentinel's own session-start output:

```bash
# Check the token budget setting
echo ${SENTINEL_TOKEN_BUDGET:-2000}
```

```
Sentinel Session-Start Output
Token budget:              <budget> tokens
Open investigations:       <count> (~<tokens> tk)
Gotchas loaded:            <count> (~<tokens> tk)
Session recovery:          <present/none> (~<tokens> tk)
Learned patterns:          <count> (~<tokens> tk)
Team activity:             <days> days (~<tokens> tk)
Fact check output:         <present/none> (~<tokens> tk)
────────────────────────────────────────────────────────
Estimated actual output:   ~<tokens> tk / <budget> tk budget
```

## 6. Vault Size

Count entries in each vault directory:

```
Vault Inventory
Directory              Entries   Total Size    Tokens
investigations/        <n>       <chars> ch    ~<tokens> tk
  resolved/            <n>       (not loaded at start)
gotchas/               <n>       <chars> ch    ~<tokens> tk
decisions/             <n>       (loaded on demand)
workflows/             <n>       (loaded on demand)
quality/               <n>       <chars> ch    ~<tokens> tk
patterns/learned/      <n>       (high-confidence only)
architecture/          <n>       (loaded on demand)
────────────────────────────────────────────────────────
Vault total:           <n> files, ~<tokens> tk if all loaded
Session-start subset:  ~<tokens> tk (within budget)
```

## 7. Total Context Budget

Summarize all sources:

```
TOTAL CONTEXT OVERHEAD (before user types anything)
Source                      Tokens     % of 200K window
CLAUDE.md (base)            <n>        <n>%
CLAUDE.md (@ eager loads)   <n>        <n>%
Global rules                <n>        <n>%
Project rules               <n>        <n>%
MCP tool names              <n>        <n>%
Plugin metadata             <n>        <n>%
Sentinel session-start      <n>        <n>%
System prompt (estimated)   ~3,000     1.5%
────────────────────────────────────────────────────
TOTAL                       <n>        <n>%
Remaining for work:         <n>        <n>%
```

## 8. Recommendations

Based on the audit, generate a prioritized list of recommendations. Only include recommendations that apply:

### High Impact (>1,000 tokens saved)

- **Convert @ references to backtick paths** — If CLAUDE.md has `@` references, each eagerly loads ~500-3000 tokens. Converting to backtick paths enables progressive disclosure (loaded only when the workflow is actually needed).
  - Savings: `<total eager load tokens>` tokens
  - How: Replace `@vault/workflows/bug-fix.md` with `` `vault/workflows/bug-fix.md` ``

- **Reduce vault token budget** — If the session-start output is consistently under budget, lower `SENTINEL_TOKEN_BUDGET` in `.sentinel.json`.
  - Current budget: `<budget>` tokens. Actual usage: `<actual>` tokens.
  - How: `/sentinel-config set token_budget <lower_value>`

- **Resolve open investigations** — Each open investigation consumes tokens at session start. Resolving them moves them to `resolved/` where they're only counted, not loaded.
  - Open: `<count>` investigations consuming ~`<tokens>` tokens
  - How: Review and resolve completed investigations

### Medium Impact (200-1,000 tokens saved)

- **Prune stale gotchas** — Gotchas for code areas that no longer exist waste tokens.
  - How: Run `/sentinel-prune` to detect and archive stale entries

- **Disable unused MCP servers** — MCP servers that are never used still contribute tool names to context.
  - Unused candidates: (list any servers whose tools were not invoked in recent sessions)
  - How: Remove from `.mcp.json` or `~/.claude/mcp.json`

### Low Impact (<200 tokens saved)

- **Archive old session recovery files** — Recovery files >7 days old are auto-archived by pruning, but manual cleanup helps if pruning hasn't run.
  - How: Run `/sentinel-prune` or delete `vault/session-recovery/` files manually

## Output Format

Present the full audit as a formatted report. End with:

```
Context Audit Complete
Total overhead: ~<n> tokens (<n>% of 200K context window)
Top recommendation: <highest-impact recommendation>
Run /sentinel-config to adjust settings.
```
