---
name: sentinel-workflow-security-audit
description: Proactive security audit workflow — scope, OWASP Top 10 checklist, automated scanning, document. Use whenever the user says "security audit", "security review", "check for vulnerabilities", "pen test", "OWASP", "injection risk", "IDOR", "XSS check", "auth review", "secrets scan", or otherwise asks for a security pass — even if they don't explicitly say "workflow". Also applies before major releases, after security incidents, and whenever new auth/user-input/external-API code is introduced. Walks the full OWASP Top 10 and runs dependency audits. Four steps — scope, OWASP checklist, automated scanning, document.
workflow: true
workflow-steps: 4
allowed-tools: Read Grep Glob Bash Edit Write MultiEdit TodoWrite
origin: sentinel
---

# Security Audit Workflow

Proactive security review of a module, feature, or the full application.

This is a Sentinel workflow skill. When it activates, the `sentinel-workflow-runner` protocol drives execution — creates a run directory, checkpoints progress after each step, and supports resumption across sessions. You do not need to invoke the runner explicitly; it activates alongside this skill.

## Protocol summary

At the top of the workflow, create a new run:

```bash
RUN_ID=$(bash "${CLAUDE_PLUGIN_ROOT}/scripts/workflow-state.sh" start security-audit)
```

Before each numbered step, call `step-start`. After each step completes, call `step-complete` (with an artifact path if you produced one). After the final step, call `finish <run-id> completed`. On failure, call `step-fail` and follow the failure-handling rules in each section below.

Full protocol details: see `sentinel-workflow-runner` skill.

---

## When to Trigger

- New authentication or authorization flow
- New external API integration (OAuth tokens, API keys)
- New user input handling (forms, file uploads, query parameters)
- New database queries (injection risk)
- Before a major release
- After a security incident

## 1. Scope

```bash
bash "${CLAUDE_PLUGIN_ROOT}/scripts/workflow-state.sh" step-start "$RUN_ID" 1 "Scope"
```

- [ ] Identify the module/feature to audit
- [ ] Read the relevant architecture files in `vault/architecture/`
- [ ] Check `vault/gotchas/` for known security constraints in this area
- [ ] List all entry points (API endpoints, form handlers, webhook receivers)

**Write an artifact**: `vault/workflows/runs/$RUN_ID/artifacts/step-1-scope.md` with the audit scope, entry points list, and relevant vault context.

```bash
bash "${CLAUDE_PLUGIN_ROOT}/scripts/workflow-state.sh" step-complete "$RUN_ID" 1 "artifacts/step-1-scope.md"
```

## 2. OWASP Top 10 Checklist

```bash
bash "${CLAUDE_PLUGIN_ROOT}/scripts/workflow-state.sh" step-start "$RUN_ID" 2 "OWASP Top 10 Checklist"
```

### A01: Broken Access Control
- [ ] All endpoints require authentication
- [ ] Authorization checks verify user owns the resource
- [ ] No IDOR vulnerabilities (user can't access another user's data by changing IDs)

### A02: Cryptographic Failures
- [ ] No secrets in source code (API keys, tokens, passwords)
- [ ] Tokens stored securely (not in localStorage for sensitive tokens)
- [ ] HTTPS enforced for all external API calls

### A03: Injection
- [ ] All SQL queries use parameterized queries (ORM or prepared statements)
- [ ] No string interpolation in queries
- [ ] User input sanitized before HTML rendering (XSS prevention)
- [ ] No shell command injection (no `os.system()` or `subprocess` with user input)

### A04: Insecure Design
- [ ] Rate limiting on all public endpoints
- [ ] Error messages don't leak internal details (stack traces, DB schema, file paths)
- [ ] Fail securely (deny by default, not allow by default)

### A05: Security Misconfiguration
- [ ] CSP headers configured if serving HTML
- [ ] CORS configured correctly (not `*` in production)
- [ ] Debug mode disabled in production
- [ ] Default credentials changed

### A06: Vulnerable Components
- [ ] `pip audit` / `npm audit` / `yarn audit` show no critical vulnerabilities
- [ ] Dependencies are reasonably up to date

### A07: Authentication Failures
- [ ] Auth properly integrated and tested
- [ ] OAuth flows follow platform best practices
- [ ] Token refresh handles expiry correctly

### A08: Data Integrity Failures
- [ ] API responses validated before processing
- [ ] No deserialization of untrusted data without schema validation

### A09: Logging & Monitoring
- [ ] Security events logged (failed auth, permission denied, unusual access patterns)
- [ ] Logs don't contain secrets or PII
- [ ] Error logs are structured (structured logging, not print)

### A10: SSRF
- [ ] No user-controlled URLs used in server-side HTTP requests without validation
- [ ] Webhook URLs validated against allowlist

**Write an artifact**: `artifacts/step-2-owasp.md` with each OWASP category, the check result, and any findings with severity.

```bash
bash "${CLAUDE_PLUGIN_ROOT}/scripts/workflow-state.sh" step-complete "$RUN_ID" 2 "artifacts/step-2-owasp.md"
```

## 3. Automated Scanning

```bash
bash "${CLAUDE_PLUGIN_ROOT}/scripts/workflow-state.sh" step-start "$RUN_ID" 3 "Automated Scanning"
```

```bash
# Python dependency audit
pip audit

# Node dependency audit
npm audit
# or
yarn audit

# Search for common dangerous patterns
grep -r "os.system\|subprocess.call\|eval(" src/
grep -r "dangerouslySetInnerHTML" src/
```

- [ ] Address all CRITICAL findings immediately
- [ ] Address HIGH findings before shipping
- [ ] Document MEDIUM/LOW findings for future cleanup

**Write an artifact**: `artifacts/step-3-scan.md` with raw scanner output and a triaged list of findings by severity.

```bash
bash "${CLAUDE_PLUGIN_ROOT}/scripts/workflow-state.sh" step-complete "$RUN_ID" 3 "artifacts/step-3-scan.md"
```

## 4. Document

```bash
bash "${CLAUDE_PLUGIN_ROOT}/scripts/workflow-state.sh" step-start "$RUN_ID" 4 "Document"
```

- [ ] Log findings in `vault/investigations/` if vulnerabilities found
- [ ] Add new security constraints to `vault/gotchas/`
- [ ] Update `vault/changelog/` with security fixes

**Write an artifact**: `artifacts/step-4-document.md` listing all vault entries touched (created, updated, deleted).

```bash
bash "${CLAUDE_PLUGIN_ROOT}/scripts/workflow-state.sh" step-complete "$RUN_ID" 4 "artifacts/step-4-document.md"
bash "${CLAUDE_PLUGIN_ROOT}/scripts/workflow-state.sh" finish "$RUN_ID" completed
```

#workflow #security #audit
