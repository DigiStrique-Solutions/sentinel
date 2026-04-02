# Security Audit Workflow

Proactive security review of a module, feature, or the full application.

## When to Trigger

- New authentication or authorization flow
- New external API integration (OAuth tokens, API keys)
- New user input handling (forms, file uploads, query parameters)
- New database queries (injection risk)
- Before a major release

## 1. Scope

- [ ] Identify the module/feature to audit
- [ ] Read the relevant architecture files in `vault/architecture/`
- [ ] Check `vault/gotchas/` for known security constraints
- [ ] List all entry points (API endpoints, form handlers, webhook receivers)

## 2. OWASP Top 10 Checklist

### A01: Broken Access Control
- [ ] All endpoints require authentication
- [ ] Authorization checks verify user owns the resource
- [ ] No IDOR vulnerabilities (user can't access another user's data by changing IDs)

### A02: Cryptographic Failures
- [ ] No secrets in source code (API keys, tokens, passwords)
- [ ] Tokens stored securely
- [ ] HTTPS enforced for all external API calls

### A03: Injection
- [ ] All SQL queries use parameterized queries
- [ ] No string interpolation in queries
- [ ] User input sanitized before HTML rendering (XSS prevention)
- [ ] No shell command injection

### A04: Insecure Design
- [ ] Rate limiting on public endpoints
- [ ] Error messages don't leak internal details
- [ ] Fail securely (deny by default)

### A05: Security Misconfiguration
- [ ] Security headers configured (CSP, CORS, etc.)
- [ ] Debug mode disabled in production
- [ ] Default credentials changed

### A06: Vulnerable Components
- [ ] Dependency audit shows no critical vulnerabilities
- [ ] Dependencies are reasonably up to date

### A07: Authentication Failures
- [ ] Auth properly integrated
- [ ] OAuth flows follow platform best practices
- [ ] Token refresh handles expiry correctly

### A08: Data Integrity Failures
- [ ] API responses validated before processing
- [ ] No deserialization of untrusted data without schema validation

### A09: Logging & Monitoring
- [ ] Security events logged (failed auth, permission denied)
- [ ] Logs don't contain secrets or PII
- [ ] Error logs are structured

### A10: SSRF
- [ ] No user-controlled URLs used in server-side HTTP requests without validation

## 3. Automated Scanning

- [ ] Run dependency audit tool (`pip audit`, `yarn audit`, `cargo audit`, etc.)
- [ ] Search for common dangerous patterns in the codebase
- [ ] Address all critical findings immediately

## 4. Document

- [ ] Log findings in `vault/investigations/` if vulnerabilities found
- [ ] Add new security constraints to `vault/gotchas/`

#workflow #security #audit
