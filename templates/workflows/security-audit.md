# Security Audit Workflow

Proactive security review of a module, feature, or the full application.

## When to Trigger

- New authentication or authorization flow
- New external API integration (OAuth tokens, API keys)
- New user input handling (forms, file uploads, query parameters)
- New database queries (injection risk)
- Before a major release
- After a security incident

## 1. Scope

- [ ] Identify the module/feature to audit
- [ ] Read the relevant architecture files in `vault/architecture/`
- [ ] Check `vault/gotchas/` for known security constraints in this area
- [ ] List all entry points (API endpoints, form handlers, webhook receivers)

## 2. OWASP Top 10 Checklist

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

## 3. Automated Scanning

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

## 4. Document

- [ ] Log findings in `vault/investigations/` if vulnerabilities found
- [ ] Add new security constraints to `vault/gotchas/`
- [ ] Update `vault/changelog/` with security fixes

#workflow #security #audit
