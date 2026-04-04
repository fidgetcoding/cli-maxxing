# Security Safety Check

When this skill is invoked, run a comprehensive security audit on the current working directory. Detect the project type automatically and run all applicable checks.

## Invocation

This skill activates when the user types `/safetycheck`, or says "run a safety check", "security audit", "safetycheck", or "check this project for security issues".

## Execution

### Step 1 — Detect Project Type

Determine what kind of project this is by checking for:
- `package.json` → Node.js
- `requirements.txt` / `pyproject.toml` → Python
- `*.sh` files at root → Shell scripts
- `Cargo.toml` → Rust
- `go.mod` → Go
- If none match, treat as generic and run filesystem-level checks only

### Step 2 — Run All 8 Security Checks

Run each check against the current working directory. Use Grep, Read, Glob, and Bash tools. Report findings in a severity-rated table at the end.

---

#### Check 1: Exposed API Keys

Scan source files and git history for hardcoded secrets.

**Source scan** — Grep all source files for these patterns:
- `AIzaSy[a-zA-Z0-9_-]{30,}` (Firebase/Google API keys)
- `sk-[a-zA-Z0-9]{20,}` (OpenAI keys)
- `pk_live_`, `sk_live_`, `pk_test_`, `sk_test_` (Stripe keys)
- `ghp_[a-zA-Z0-9]{36}`, `gho_`, `github_pat_` (GitHub tokens)
- `AKIA[0-9A-Z]{16}` (AWS access keys)
- `xox[bpsa]-[a-zA-Z0-9-]+` (Slack tokens)
- Hardcoded `Bearer` tokens with actual values
- Any `password = "..."` or `secret = "..."` with literal values (not env vars)

Exclude: test fixtures, example files, regex patterns in security scanners, `.env.example` files with placeholder values.

**Git history scan** — Run:
```bash
git log -p --all -S "API_KEY" -S "SECRET" -S "TOKEN" -S "sk-" --max-count=30 2>/dev/null | grep -E "^\+" | grep -ivE "(process\.env|os\.environ|\.env\.example|placeholder|your_|example|test)" | head -20
```

**Tracked .env check** — Run:
```bash
git ls-files 2>/dev/null | grep -iE "\.env$"
```

**Severity**: CRITICAL if real keys found in source or git history. HIGH if .env is tracked. PASS if clean.

---

#### Check 2: Rate Limiting

**Detect endpoints** — Grep for: `express`, `fastify`, `http.createServer`, `app.listen`, `app.get(`, `app.post(`, `router.`

**If endpoints exist**, check for rate limiting:
- Grep for: `rate-limit`, `rateLimit`, `throttle`, `@upstash/ratelimit`, `bottleneck`, `p-queue`
- Check package.json dependencies for rate-limit packages

**Detect outbound APIs** — Grep for: `fetch(`, `axios`, `http.request`, `got(`
- If outbound calls exist, check for retry/backoff logic and 429 handling

**Severity**: HIGH if public endpoints exist without rate limiting. MEDIUM if outbound APIs lack 429 handling. N/A if no endpoints.

---

#### Check 3: Input Sanitization

Scan for dangerous patterns:
- `eval(` with non-constant arguments
- `execSync(` or `exec(` with string concatenation (not `execFileSync` with array)
- `innerHTML` assignments without `escapeHtml` or DOMPurify
- SQL queries built with string concatenation (`"SELECT * FROM " + table`)
- Template literals in URL paths with unsanitized variables: `` `/api/${userInput}` ``
- `child_process.exec(` with template literals or string concat
- `dangerouslySetInnerHTML` without sanitization
- `source` of untrusted files in shell scripts

Check for validation:
- Grep for: `zod`, `joi`, `yup`, `ajv`, `validator`, `encodeURIComponent`, `escapeHtml`, `sanitize`

**Severity**: CRITICAL for eval/exec with user input. HIGH for unsanitized URL paths. MEDIUM for missing validation library. PASS if clean.

---

#### Check 4: RLS / Database Security

**Detect database usage** — Check package.json and source for: `supabase`, `prisma`, `drizzle`, `knex`, `sequelize`, `typeorm`, `pg`, `mysql`, `sqlite`, `mongoose`, `mongodb`

**If Supabase**: Check for migration files, look for `ENABLE ROW LEVEL SECURITY` in SQL files, check for policy definitions.

**If any database**: Check for parameterized queries vs string concatenation.

**Severity**: CRITICAL if database found without RLS/access control. HIGH if queries use string concat. N/A if no database.

---

#### Check 5: Dependency Vulnerabilities

**Node.js**: Run `npm audit --json 2>/dev/null` — parse results for high/critical vulnerabilities.
**Python**: Run `pip audit 2>/dev/null` if available.
**Check lockfile**: Verify `package-lock.json`, `yarn.lock`, or equivalent exists.
**Check outdated**: Run `npm outdated 2>/dev/null | head -10`

**Severity**: CRITICAL if known high/critical vulns. MEDIUM if no lockfile. LOW if outdated packages. PASS if clean.

---

#### Check 6: Gitignore Hygiene

Read `.gitignore` and verify it includes:
- `.env` and `.env.*`
- `*.pem`, `*.key`, `*.cert`
- `node_modules/` (Node.js)
- `.DS_Store`
- IDE folders (`.vscode/`, `.idea/`)

Check for files that SHOULD be ignored but are tracked:
```bash
git ls-files 2>/dev/null | grep -iE "\.(env|pem|key|cert|p12|pfx|keystore)$"
```

If the project is published to npm, check for `files` field in package.json or `.npmignore`.

**Severity**: HIGH if .env not in .gitignore. MEDIUM if *.pem/*.key missing. LOW if minor patterns missing. PASS if complete.

---

#### Check 7: CI/CD and GitHub Security

Check for:
- `.github/workflows/` directory — any CI at all?
- `.github/dependabot.yml` — automated dependency updates?
- `SECURITY.md` — vulnerability disclosure policy?
- `.github/CODEOWNERS` — code ownership rules?
- Branch protection (if `gh` CLI available): `gh api repos/{owner}/{repo}/branches/main/protection 2>/dev/null`

**Severity**: HIGH if no CI/CD and project has dependencies. MEDIUM if missing dependabot or SECURITY.md. LOW if missing CODEOWNERS. PASS if all present.

---

#### Check 8: Error Handling

Scan for patterns that leak internal details:
- `res.text()` or `res.json()` results thrown directly in error messages
- `catch (e) { res.send(e.message) }` or `catch (e) { return e.stack }`
- `console.error` of full error objects in production code paths
- Error responses that include raw API response bodies

**Severity**: MEDIUM if raw error bodies are exposed to users. LOW if only logged to console. PASS if errors are sanitized.

---

### Step 3 — Report Findings

Output a markdown table:

```
| # | Check | Status | Findings |
|---|-------|--------|----------|
| 1 | Exposed API Keys | PASS/CRITICAL/HIGH/MEDIUM/LOW | Details... |
| 2 | Rate Limiting | ... | ... |
| ... | ... | ... | ... |
```

Then list specific findings with file paths and line numbers.

### Step 4 — Offer Fixes

For each finding that has an auto-fixable solution, offer to fix it:
- Missing .gitignore patterns → offer to add them
- Missing SECURITY.md → offer to create one
- Missing dependabot.yml → offer to create one
- execSync with string concat → offer to replace with execFileSync
- Missing input validation → offer to add validation functions

Ask the user before making any changes.
