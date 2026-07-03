---
name: safetycheck
description: "Comprehensive security audit — scans any project for exposed API keys, missing rate limiting, input sanitization gaps, dependency vulnerabilities, and insecure configurations. Auto-activates 12 MCP-specific checks on MCP projects."
user_invocable: true
---

# Security Safety Check

When this skill is invoked, run a comprehensive security audit on the current working directory. Detect the project type automatically and run all applicable checks.

## Invocation

This skill activates when the user types `/safetycheck`, or says "run a safety check", "security audit", "safetycheck", or "check this project for security issues".

## Execution

### Step 0 — Run precheck.sh (if present)

Before any other check, look for a `scripts/precheck.sh` in the git repo root:

```bash
REPO_ROOT=$(git rev-parse --show-toplevel 2>/dev/null || pwd)
```

If `$REPO_ROOT/scripts/precheck.sh` exists:
1. Run it: `bash "$REPO_ROOT/scripts/precheck.sh"`
2. Capture exit code and output
3. If exit code is non-zero, report each failing check as **CRITICAL** (secrets) or **HIGH** (other) in the final results table — label the source as "precheck.sh"
4. Print the precheck.sh output verbatim under a `### Precheck Results` header before the main audit begins
5. Continue with Steps 1–4 regardless of precheck result (don't abort — surface everything)

If `scripts/precheck.sh` does not exist, skip Step 0 silently.

---

### Step 1 — Detect Project Type

Determine what kind of project this is by checking for:
- `package.json` → Node.js
- `requirements.txt` / `pyproject.toml` → Python
- `*.sh` files at root → Shell scripts
- `Cargo.toml` → Rust
- `go.mod` → Go
- If none match, treat as generic and run filesystem-level checks only

**MCP Detection** — After detecting the base project type, check for MCP signals:
- `@modelcontextprotocol/sdk` or `fastmcp` in package.json dependencies
- `from mcp import` or `from mcp.server` in Python files
- `new McpServer(`, `server.tool(`, `McpServer` in JS/TS files
- `.mcp.json`, `claude_desktop_config.json`, `.cursor/mcp.json` file presence
- `@mcp.tool` decorator in Python

If MCP detected: activate Phase 0 + Checks 13-24, AND add MCP subsections to Checks 1, 3, 5, 6, 8 (Checks 2 and 11 also carry inline MCP notes).

Two scan modes:
- **MCP Server Mode** — codebase IS an MCP server (SDK imports, tool registrations found)
- **MCP Consumer Mode** — project has `.mcp.json` or `claude_desktop_config.json` config files

A project can be both.

### Step 2 — Run All Checks

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

Exclude a match only when its **value** is a placeholder (`your_`, `xxx`, `changeme`, `<...>`, `example`, `dummy`) or the file is `*.env.example` / `.sample` / `.template`. A real-looking key is still a finding even under `tests/`, `examples/`, or a fixture path — never skip by directory or filename alone. Skip this skill's own regex signature list (a scanner's patterns are not a leak).

**Git history scan** — Run:
```bash
git log -p --all -G "API_KEY|SECRET|TOKEN|sk-" --max-count=30 2>/dev/null | grep -E "^\+[^+]" | grep -iE '(AIzaSy[a-zA-Z0-9_-]{30,}|sk-[a-zA-Z0-9]{20,}|(pk|sk)_(live|test)_|gh[ports]_[a-zA-Z0-9]{20,}|AKIA[0-9A-Z]{16}|xox[bpsa]-[a-zA-Z0-9-]+|(password|secret)[[:space:]]*=[[:space:]]*["'"'"'])' | grep -ivE "(process\.env|os\.environ|\.env\.example|placeholder|your_|example|test)" | head -20
```

**Tracked .env check** — Run:
```bash
git ls-files 2>/dev/null | grep -iE "\.env$"
```

**MCP Config scan** (if MCP detected) — Scan `.mcp.json`, `claude_desktop_config.json`, `.cursor/mcp.json` for hardcoded secrets in `env` blocks:
```bash
grep -rniE --exclude-dir=node_modules --exclude-dir=.git '(sk-[a-zA-Z0-9]{20,}|AKIA[0-9A-Z]{16}|ghp_[a-zA-Z0-9]{36}|AIzaSy[a-zA-Z0-9_-]{30,}|xox[bpsa]-[a-zA-Z0-9-]+)' . --include=".mcp.json" --include="claude_desktop_config.json" 2>/dev/null
```

Check if MCP configs are tracked in git:
```bash
git ls-files 2>/dev/null | grep -iE "(\.mcp\.json|claude_desktop_config\.json)"
```

**Client bundle scan** — secrets shipped to the browser/mobile bundle. Public-prefix env vars are embedded in the client bundle at build time:
```bash
# Public-prefix env vars carrying secret-looking names.
# Exclusion is VALUE-anchored: drop only when the whole value is a placeholder (anchored to end-of-value),
# or the FILE is .env.example/.sample/.template. A real secret prefixed with "xxx"/"example" is NOT dropped.
grep -rniE --exclude-dir=node_modules --exclude-dir=.git '(NEXT_PUBLIC_|VITE_|REACT_APP_|EXPO_PUBLIC_|NUXT_PUBLIC_|GATSBY_)[A-Z0-9_]*(SECRET|SERVICE_ROLE|PRIVATE|PASSWORD|TOKEN)' . --include="*.ts" --include="*.js" --include="*.tsx" --include="*.jsx" --include=".env*" 2>/dev/null | grep -viE '\.env\.(example|sample|template):' | grep -viE '=[[:space:]]*(your_[a-z0-9_]*|placeholder|changeme|x{3,}|example|dummy|<[^>]*>)[[:space:]]*$'

# Server-only keys referenced from client code paths
grep -rniE --exclude-dir=node_modules --exclude-dir=.git '(service_role|sk_live_|sk_test_)' src/ app/ components/ pages/ 2>/dev/null
```

Publishable keys (Supabase anon key, Stripe `pk_*`) are fine client-side. `service_role`, `sk_*`, and anything named SECRET/PRIVATE never are. An opaque/generic `*_TOKEN` with no vendor signature is not auto-CRITICAL (it may be a public token) but still warrants a human look.

**Gitignored secrets — read them directly:** `.env` and `.mcp.json` are usually gitignored, and some `grep` builds (ripgrep/ugrep-backed shims, or grep run through a wrapper that honors `.gitignore`) silently skip gitignored files — exactly the ones most likely to hold real secrets. For every secret scan above, run through `/usr/bin/grep` (BSD grep ignores `.gitignore`) or `Read` the `.env`/config files directly; do not trust a clean `grep --include=".env*"` result alone.

**Severity**: CRITICAL if real keys found in source, git history, or MCP config env blocks, or if server-only secrets are reachable from the client bundle (SECRET/SERVICE_ROLE/PRIVATE/PASSWORD matches). HIGH if .env or MCP config is tracked, or for TOKEN-named public-prefix matches (review first — public tokens like Mapbox are legitimately client-side). PASS if clean.

---

#### Check 2: Rate Limiting

**Detect endpoints** — Grep for: `express`, `fastify`, `http.createServer`, `app.listen`, `app.get(`, `app.post(`, `router.`

**If endpoints exist**, check for rate limiting:
- Grep for: `rate-limit`, `rateLimit`, `throttle`, `@upstash/ratelimit`, `bottleneck`, `p-queue`
- Check package.json dependencies for rate-limit packages

**Detect outbound APIs** — Grep for: `fetch(`, `axios`, `http.request`, `got(`
- If outbound calls exist, check for retry/backoff logic and 429 handling

Note: For MCP servers using HTTP transport, the same rate-limit checks apply to the HTTP layer.

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

**MCP Tool Handler scan** (if MCP Server Mode) — Grep for tool handlers using arguments directly without validation:
```bash
# Tool handlers passing args to dangerous sinks
grep -rniE --exclude-dir=node_modules --exclude-dir=.git '(args\.\w+|arguments\.\w+)' --include="*.ts" --include="*.js" --include="*.py" . | grep -E "(exec|execSync|spawn|readFile|writeFile|query|SQL|eval)"

# Tool handlers without inputSchema (missing 2nd arg in server.tool)
grep -rniE --exclude-dir=node_modules --exclude-dir=.git 'server\.tool\([^,]+,\s*(async\s*)?\(' --include="*.ts" --include="*.js" .

# No validation library when server.tool() calls exist
```

Check if any validation library (zod, joi, ajv, pydantic, BaseModel) is present when `server.tool()` calls exist.

**Severity**: CRITICAL for eval/exec with user input or unvalidated MCP tool args flowing to exec/SQL/filesystem. HIGH for unsanitized URL paths. MEDIUM for missing validation library. PASS if clean.

---

#### Check 4: RLS / Database Security

**Detect database usage** — Check package.json and source for: `supabase`, `prisma`, `drizzle`, `knex`, `sequelize`, `typeorm`, `pg`, `mysql`, `sqlite`, `mongoose`, `mongodb`

**If Supabase**: Check for migration files, look for `ENABLE ROW LEVEL SECURITY` in SQL files, check for policy definitions.

**If any database**: Check for parameterized queries vs string concatenation.

**Severity**: CRITICAL if database found without RLS/access control. HIGH if queries use string concat. N/A if no database.

---

#### Check 5: Dependency Vulnerabilities

**Node.js**: Run `npm audit --json 2>/dev/null` — parse results for high/critical vulnerabilities. If it returns `{"error":{"code":"ENOLOCK"}}` (no lockfile), treat as "skipped", not PASS.
**Python**: Run `command -v pip-audit >/dev/null 2>&1 && pip-audit 2>/dev/null || echo "pip-audit not installed"` — the tool is `pip-audit` (not `pip audit`); if absent, report unavailable rather than passing silently.
**Check lockfile**: Verify `package-lock.json`, `yarn.lock`, or equivalent exists.
**Check outdated**: Run `npm outdated 2>/dev/null | head -10`

**MCP SDK version check** (if MCP detected):
```bash
node -e "const p=require('./package.json'); const v=p.dependencies?.['@modelcontextprotocol/sdk']||p.devDependencies?.['@modelcontextprotocol/sdk']; if(v) console.log('MCP SDK version: '+v);" 2>/dev/null
```
- TypeScript SDK < 1.24.0 → CRITICAL: CVE-2025-66414 (DNS rebinding, host header validation disabled by default; fixed in 1.24.0)
- Python SDK < 1.23.0 → HIGH: CVE-2025-66416 (DNS rebinding; fixed in 1.23.0)
- Flag `@modelcontextprotocol/sdk` (TS) version 1.23.x or below, or Python `mcp` below 1.23.0

Check for non-official / lookalike MCP package names — the intended dep should be `@modelcontextprotocol/sdk` or `fastmcp`. Confirm before flagging: `mcp-sdk` and `model-context-protocol` are real but non-official packages (not confirmed malicious), and `fastmcp` (no hyphen) is legitimate.
```bash
grep -E '"(model-context-protocol|mcp-sdk|fast-mcp)"' package.json 2>/dev/null
```

**Severity**: CRITICAL if known high/critical vulns or vulnerable MCP SDK. HIGH if a non-official / lookalike MCP package name is present (confirm the intended dep). MEDIUM if no lockfile. LOW if outdated packages. PASS if clean.

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

**MCP Config gitignore check** (if MCP Consumer Mode) — Verify MCP config files are in .gitignore:
```bash
git ls-files 2>/dev/null | grep -iE "(\.mcp\.json|claude_desktop_config\.json)"
```
- `.mcp.json` should be in .gitignore (may contain API keys in env blocks)
- `claude_desktop_config.json` should be in .gitignore

**Severity**: HIGH if .env or MCP config files are tracked in git. MEDIUM if *.pem/*.key missing. LOW if minor patterns missing. PASS if complete.

---

#### Check 7: CI/CD and GitHub Security

Check for:
- `.github/workflows/` directory — any CI at all?
- `.github/dependabot.yml` — automated dependency updates?
- `SECURITY.md` — vulnerability disclosure policy?
- `.github/CODEOWNERS` — code ownership rules?
- Branch protection (if `gh` CLI available): `gh api repos/{owner}/{repo}/branches/main/protection 2>/dev/null`

**Severity**: HIGH if no CI/CD and project has dependencies. MEDIUM if missing dependabot or SECURITY.md. LOW if missing CODEOWNERS, or if branch protection is disabled on the default branch (only conclusive when `gh` is authenticated with admin scope — empty output may mean no remote/auth, not "unprotected"). PASS if all present.

---

#### Check 8: Error Handling

Scan for patterns that leak internal details:
- `res.text()` or `res.json()` results thrown directly in error messages
- `catch (e) { res.send(e.message) }` or `catch (e) { return e.stack }`
- `console.error` of full error objects in production code paths
- Error responses that include raw API response bodies

**MCP Tool Error scan** (if MCP Server Mode) — Scan for raw errors in tool handler responses:
```bash
# Stack traces or raw errors in isError responses
grep -rniE --exclude-dir=node_modules --exclude-dir=.git 'isError.*true' --include="*.ts" --include="*.js" -A3 . | grep -E '(\.stack|\.message|JSON\.stringify\(e|JSON\.stringify\(err)'

# Error details in template literals within catch blocks
grep -rniE --exclude-dir=node_modules --exclude-dir=.git 'catch\s*\([^)]*\)' --include="*.ts" --include="*.js" -A5 . | grep -E '(\$\{(e|err|error)\}|\.stack|traceback)'

# Python traceback in tool returns
grep -rniE --exclude-dir=node_modules --exclude-dir=.git 'traceback\.format_exc\(\)|str\(e\)' --include="*.py" .
```

**Severity**: MEDIUM if raw error bodies or stack traces are exposed to users or in tool content. LOW if only logged to console. PASS if errors are sanitized.

---

#### Check 9: Authorization / IDOR

**Runs when endpoints exist** (same detection as Check 2).

Being logged in is not authorization — every sensitive handler must verify the user can touch the specific record.

Scan for record access keyed by request-supplied IDs:
```bash
# Record lookups driven by request params/query/body (direct-arg form)
grep -rniE --exclude-dir=node_modules --exclude-dir=.git '(findById|findByPk|findOne|findUnique)\s*\(\s*(req\.(params|query|body)|params\.|request\.)' --include="*.ts" --include="*.js" .

# ORM object-form lookups: findOne({ where: { id: req.params.id } })
grep -rniE --exclude-dir=node_modules --exclude-dir=.git '(findById|findByPk|findOne|findUnique)\s*\(\s*\{\s*where\s*:\s*\{[^}]*(req\.(params|query|body)|params\.|request\.)' --include="*.ts" --include="*.js" .

# Raw SQL keyed on request input (JS req.* AND Python request.args/form + f-string interpolation)
grep -rniE --exclude-dir=node_modules --exclude-dir=.git '(WHERE\s+id\s*=|DELETE\s+FROM|UPDATE\s+\w+\s+SET).*(req\.(params|query|body)|request\.(args|form|json|values)|\$\{|f["'"'"'])' --include="*.ts" --include="*.js" --include="*.py" .
```

For each hit, check the same handler/file for an ownership predicate: `userId`, `user_id`, `owner`, `req.user`, `session.user`, `auth.uid()`, `ctx.user`. A lookup by request-supplied ID with no ownership scoping is an IDOR candidate. Confirm the predicate is real code, not a comment or string — token presence in a comment ("no ownership check") does not count.

Check auth middleware coverage on mutating routes (`app.post/put/patch/delete`, `router.*`): `requireAuth`, `isAuthenticated`, `passport.authenticate`, `getServerSession`, `verifyToken`, `auth()`.

Flag server code that trusts client-supplied identity for access decisions:
```bash
grep -rniE --exclude-dir=node_modules --exclude-dir=.git "req\.(body|query)\.(userId|user_id|role|isAdmin|is_admin)|req\.headers\[['\"]x-user-id" --include="*.ts" --include="*.js" .
```

**Severity**: CRITICAL if mutating endpoints access records by request-supplied ID with no auth middleware, or trust client-sent userId/role. HIGH if authenticated but no ownership scoping visible (IDOR candidate — escalate to CRITICAL once confirmed exploitable). N/A if no endpoints.

---

#### Check 10: Client-Side Auth Trust

Authentication must be decided server-side. Scan for patterns where the client's word is taken for identity:

```bash
# jwt.decode used instead of jwt.verify (decode does NOT check the signature)
grep -rnE --exclude-dir=node_modules --exclude-dir=.git 'jwt\.decode\(|jwt_decode|jwtDecode' --include="*.ts" --include="*.js" .

# ...then confirm signature verification exists somewhere server-side
grep -rnE --exclude-dir=node_modules --exclude-dir=.git 'jwt\.verify\(|jwtVerify|verifyToken' --include="*.ts" --include="*.js" .

# Roles/authorization flags read from client storage (keys anchored to avoid benign 'authToken'/'adminSidebar' hits)
grep -rniE --exclude-dir=node_modules --exclude-dir=.git "(localStorage|sessionStorage)\.(get|set)Item\(['\"](role|roles|isAdmin|is_admin|admin|auth|permissions?)['\"]" --include="*.ts" --include="*.js" --include="*.tsx" --include="*.jsx" .
```

`jwtDecode` in frontend code (rendering UI from claims) is normal — the CRITICAL rating applies only when decode is the server's token check.

Frontend-only route guards (`PrivateRoute`, `ProtectedRoute`, router `beforeEach` auth checks) are fine for UX, but flag them if the API routes they front have no server-side check (cross-reference Check 9).

**Severity**: CRITICAL if `jwt.decode` is the only token check on the server, or role flags from client storage gate server-relevant actions. MEDIUM if frontend-only guards exist with unclear API coverage. PASS if verification is server-side.

---

#### Check 11: Web Security Defaults (CORS / CSRF / Cookies / Headers)

**Runs when HTTP endpoints exist** — any web app. In MCP Server Mode, defer the CORS portion to Check 21 (the MCP-specific variant) to avoid double-reporting.

**CORS**:
```bash
grep -rniE --exclude-dir=node_modules --exclude-dir=.git 'cors\(\s*\)|origin\s*:\s*["'"'"']\*["'"'"']|origin\s*:\s*true|Access-Control-Allow-Origin.*\*' --include="*.ts" --include="*.js" .
grep -rniE --exclude-dir=node_modules --exclude-dir=.git 'allow_origins\s*=\s*\["?\*"?\]' --include="*.py" .

# credentials paired with wildcard escalates to CRITICAL
grep -rniE --exclude-dir=node_modules --exclude-dir=.git 'credentials\s*:\s*true|Access-Control-Allow-Credentials' --include="*.ts" --include="*.js" .
```

**CSRF** — first detect cookie-based sessions, then confirm protection. Pure Bearer-token APIs are exempt.
```bash
# Cookie-session detection (gate)
grep -rnE --exclude-dir=node_modules --exclude-dir=.git "express-session|cookie-session|req\.session" --include="*.ts" --include="*.js" .

# Protection present? (sameSite 'none' does NOT count; comments don't count)
grep -rnE --exclude-dir=node_modules --exclude-dir=.git "require\(['\"]csurf['\"]\)|csrf\(|sameSite\s*:\s*['\"](strict|lax)" --include="*.ts" --include="*.js" .
```

**Cookie flags** — session/auth cookie config should set `httpOnly: true`, `secure: true`, and `sameSite`:
```bash
grep -rniE --exclude-dir=node_modules --exclude-dir=.git 'httpOnly\s*:\s*false|secure\s*:\s*false' --include="*.ts" --include="*.js" .
```

**Security headers** — confirm actual usage of `helmet` (Node), secure-headers middleware, or explicit CSP/HSTS config — a comment mentioning it doesn't count:
```bash
grep -rnE --exclude-dir=node_modules --exclude-dir=.git "require\(['\"]helmet['\"]\)|from ['\"]helmet['\"]|app\.use\(\s*helmet" --include="*.ts" --include="*.js" .
```

**Plain HTTP** — non-localhost `http://` URLs in production config:
```bash
grep -rniE --exclude-dir=node_modules --exclude-dir=.git '["'"'"'=]http://' --include="*.ts" --include="*.js" --include="*.json" --include=".env*" . | grep -vE 'localhost|127\.0\.0\.1|::1|\.test|example\.'
```

**Severity**: CRITICAL for wildcard CORS + `credentials: true`. HIGH for wildcard CORS without credentials, cookie sessions without CSRF protection, or `httpOnly`/`secure` explicitly false. MEDIUM for missing security headers or non-localhost plain `http://` URLs in production config/source. N/A if no endpoints.

---

#### Check 12: Sensitive Data in Logs

Log security events — never log the secrets themselves.

```bash
# Log calls referencing sensitive variables
grep -rniE --exclude-dir=node_modules --exclude-dir=.git '(console\.(log|error|warn|info)|logger\.\w+|logging\.\w+|log\.(info|warn|error|debug)|print)\(.*\b(password|passwd|secret|token|api_?key|authorization|bearer|ssn|credit)' --include="*.ts" --include="*.js" --include="*.py" .

# Whole request bodies / headers logged (highest risk on auth routes — judge context per hit)
grep -rniE --exclude-dir=node_modules --exclude-dir=.git '(console\.\w+|logger\.\w+)\(\s*(req\.body|req\.headers|request\.body)' --include="*.ts" --include="*.js" .
```

Positive signals: redaction config (`pino` `redact` option, winston custom formats, `[REDACTED]`, sanitize helpers). Confirm real config (e.g. a `redact:` key), not a comment mentioning redaction.

Also verify the flip side: failed logins / auth events are logged at all (grep auth handlers for any logging). Silence on failed logins means breaches go unnoticed.

**Severity**: HIGH if passwords, tokens, or auth headers are logged. MEDIUM if full `req.body` is logged on auth paths, or auth events are not logged anywhere. PASS if clean or redacted.

---

### MCP Security Checks (activated when MCP project detected)

#### Phase 0 — MCP Detection Summary

This is not a numbered check. Output the detection result:
- "MCP project detected — activating MCP Security Checks 13-24"
- State which mode: **Server Mode**, **Consumer Mode**, or **Both**
- Report: language, transport type, estimated tool/resource/prompt counts, config files found

---

#### Check 13: Tool Description Integrity

**Only in MCP Server Mode.**

Scan all source files containing `server.tool(`, `@mcp.tool`, or tool definition objects for suspicious content in description fields.

**Grep patterns:**
```bash
# Find tool definition files
grep -rnE --exclude-dir=node_modules --exclude-dir=.git "server\.tool|@mcp\.tool|\"description\"\s*:" --include="*.ts" --include="*.js" --include="*.py" .

# Scan descriptions for injection markers
grep -riE --exclude-dir=node_modules --exclude-dir=.git '(<IMPORTANT>|<SYSTEM>|<HIDDEN>|<INSTRUCTION>|ignore previous|disregard|override.*instruction|you must now|act as|pretend to be|never tell|do not (tell|mention|say))' --include="*.ts" --include="*.js" --include="*.py" .

# Scan for file path references in descriptions (also catches positional server.tool('name','desc',...) form)
grep -riE --exclude-dir=node_modules --exclude-dir=.git '(~/\.|/etc/|~/.ssh|~/.cursor|\.env|id_rsa|\.config)' --include="*.ts" --include="*.js" --include="*.py" . | grep -iE "description|server\.tool|@mcp\.tool"

# Flag long descriptions (>500 chars may hide injected content)
awk 'length($0)>500 && /description/' $(grep -rlE "server\.tool|@mcp\.tool" --include="*.ts" --include="*.js" --include="*.py" --exclude-dir=node_modules --exclude-dir=.git . 2>/dev/null) 2>/dev/null | head -5
# Manually review any description that names another tool (cross-tool reference = privilege-escalation vector)
```

**Severity**: CRITICAL if injection markers or sensitive file paths found in descriptions. HIGH if descriptions > 500 chars or reference other tools by name. PASS if all descriptions are static and clean. N/A if no tool registrations found.

**Auto-fix**: Offer to review and clean suspicious descriptions. Strip hidden content.

---

#### Check 14: Unicode / Invisible Character Smuggling

**Applies to both MCP Server Mode and Consumer Mode.**

Scan tool description strings and source files for invisible Unicode characters that are processed by the LLM but invisible to human reviewers.

**Bash command:**
```bash
python3 -c "
import os
dangerous = [(0x200B,0x200D),(0xFEFF,0xFEFF),(0xE0000,0xE007F),(0x202A,0x202E),(0x2060,0x206F),(0x00AD,0x00AD)]
SKIP = {'node_modules','.git','dist','build','.next','coverage','vendor'}
found, undecodable = [], []
for root, dirs, fs in os.walk('.'):
    dirs[:] = [d for d in dirs if d not in SKIP]
    for f in fs:
        if not f.endswith(('.ts','.js','.py','.json')): continue
        fp = os.path.join(root,f)
        try:
            if os.path.getsize(fp) > 2*1024*1024: continue   # skip big generated files
            raw = open(fp,'rb').read()
        except Exception: continue
        text = None
        for enc in ('utf-8','utf-16'):                        # strict decode; utf-16 catches tag-char smuggling
            try: text = raw.decode(enc); break
            except Exception: continue
        if text is None:
            undecodable.append(fp); continue                 # invalid bytes = do NOT silently pass
        body = text[1:] if text[:1]=='\ufeff' else text      # ignore a single leading BOM
        for ch in body:
            cp = ord(ch)
            if any(lo<=cp<=hi for lo,hi in dangerous):
                found.append((fp, hex(cp))); break
        if len(found) >= 50: break
    if len(found) >= 50: break
if found:
    for fp,c in found[:20]: print(f'FOUND {c} in {fp}')
elif undecodable:
    for fp in undecodable[:5]: print(f'REVIEW (undecodable bytes — possible smuggled payload): {fp}')
    print('no invisible chars in decodable files; review the above manually')
else:
    print('PASS')
"
```

**Severity**: CRITICAL if Unicode tag characters (U+E0000-U+E007F) found in tool descriptions (invisible to humans, processed by LLM). HIGH for other invisible Unicode (directional overrides, zero-width chars). PASS if clean.

---

#### Check 15: Encoded Payloads in Tool Metadata

**Only in MCP Server Mode.**

Scan tool description and parameter definition strings for encoded content that could be decoded and executed by the LLM.

**Grep patterns:**
```bash
# Base64 in description fields (30+ chars of base64)
grep -rniE --exclude-dir=node_modules --exclude-dir=.git '[A-Za-z0-9+/]{30,}={0,2}' --include="*.ts" --include="*.js" --include="*.py" . | grep -i "description"

# Hex encoding patterns
grep -rniE --exclude-dir=node_modules --exclude-dir=.git '(\\x[0-9a-fA-F]{2}){4,}|0x[0-9a-fA-F]{8,}' --include="*.ts" --include="*.js" --include="*.py" .

# Decode/execute instructions in descriptions
grep -rniE --exclude-dir=node_modules --exclude-dir=.git '(decode|execute|eval|interpret|run this)' --include="*.ts" --include="*.js" --include="*.py" . | grep -i "description"
```

**Severity**: HIGH if Base64 or hex-encoded patterns found in tool metadata. MEDIUM if descriptions reference decoding operations. PASS if clean.

**Auto-fix**: Offer to decode and inspect suspicious strings for review.

---

#### Check 16: MCP Transport Security

**Only in MCP Server Mode.**

Verify TLS is enforced and DNS rebinding protection is active.

**Checks:**
```bash
# Check for HTTP (non-HTTPS, non-localhost) in MCP configs
grep -rniE --exclude-dir=node_modules --exclude-dir=.git '"url"\s*:\s*"http://' . --include=".mcp.json" --include="claude_desktop_config.json" 2>/dev/null | grep -vE '(localhost|127\.0\.0\.1|::1)'

# Check for 0.0.0.0 binding without auth
grep -rniE --exclude-dir=node_modules --exclude-dir=.git '(0\.0\.0\.0|host:\s*["'"'"']0\.0\.0\.0)' --include="*.ts" --include="*.js" --include="*.py" .

# Check for DNS rebinding protection
grep -rnE --exclude-dir=node_modules --exclude-dir=.git "enableDnsRebindingProtection|localhostHostValidation|hostHeaderValidation|createMcpExpressApp" --include="*.ts" --include="*.js" .

# Check MCP SDK version for DNS rebinding CVE
node -e "const v=require('./package.json').dependencies?.['@modelcontextprotocol/sdk']; if(v) console.log(v);" 2>/dev/null
```

MCP TypeScript SDK < 1.24.0 = CRITICAL: CVE-2025-66414 (DNS rebinding protection disabled by default; fixed in 1.24.0).

**Severity**: CRITICAL for HTTP URLs to remote servers + SDK < 1.24.0. HIGH for 0.0.0.0 binding without auth or missing DNS rebinding protection. N/A for stdio-only servers.

**Auto-fix**: Offer to add `hostHeaderValidation` middleware. Offer to upgrade SDK.

---

#### Check 17: MCP Authentication

**Only in MCP Server Mode + HTTP transport detected.**

First detect HTTP transport:
```bash
grep -rnE --exclude-dir=node_modules --exclude-dir=.git "StreamableHTTPServerTransport|SSEServerTransport|createMcpExpressApp|app\.listen|app\.post.*mcp|app\.get.*sse" --include="*.ts" --include="*.js" .
```

If HTTP transport found, check for auth:
```bash
grep -rnE --exclude-dir=node_modules --exclude-dir=.git "mcpAuthRouter|requireBearerAuth|OAuthServerProvider|verifyAccessToken|bearerAuth|express-jwt|passport|jsonwebtoken|jwt\.verify" --include="*.ts" --include="*.js" .
```

If HTTP transport exists but NO auth patterns found: **CRITICAL**.
If only stdio transport (StdioServerTransport): **N/A**.

**Severity**: CRITICAL if HTTP-based MCP server has no authentication. N/A for stdio-only.

**Auto-fix**: Offer to add basic bearer token auth middleware.

---

#### Check 18: Token Scope & Lifecycle

**Applies to MCP Consumer Mode.**

Check for over-privileged tokens, missing expiration, and insecure storage.

```bash
# Check for wildcard/broad OAuth scopes in MCP config or auth code
grep -rniE --exclude-dir=node_modules --exclude-dir=.git '(mail\.google\.com/|calendar\.google\.com/|drive\.google\.com/|scope.*\*|scope.*"all"|scope.*"full")' --include="*.ts" --include="*.js" --include="*.py" --include=".mcp.json" . 2>/dev/null

# Check for access tokens stored in plaintext
grep -rniE --exclude-dir=node_modules --exclude-dir=.git '("access_token"\s*:\s*"[^"]{20,}"|token\s*=\s*["'"'"'][^"'"'"']{20,})' . --include=".mcp.json" --include="claude_desktop_config.json" 2>/dev/null

# Check for long-lived (>=24h) or non-expiring tokens
grep -rniE --exclude-dir=node_modules --exclude-dir=.git '(expires_in.*86400|expires_in.*[0-9]{6,}|no.*expir|never.*expir)' --include="*.ts" --include="*.js" .
```

**Severity**: CRITICAL for plaintext access tokens in config files. HIGH for broad OAuth scopes or tokens with no expiry. PASS if scoped and rotated.

---

#### Check 19: MCP Input Schema Validation

**Only in MCP Server Mode.**

Verify all tools define and enforce input schemas.

```bash
# Find all tool registrations
grep -nE --exclude-dir=node_modules --exclude-dir=.git "server\.tool|@mcp\.tool|setRequestHandler.*ListTools" --include="*.ts" --include="*.js" --include="*.py" -r .

# Check for inputSchema / validation library usage
grep -rnE --exclude-dir=node_modules --exclude-dir=.git "inputSchema|z\.object|Joi\.object|ajv\.compile|BaseModel|pydantic" --include="*.ts" --include="*.js" --include="*.py" .

# Check for additionalProperties: false (strict schemas)
grep -rn --exclude-dir=node_modules --exclude-dir=.git "additionalProperties.*false" --include="*.ts" --include="*.js" --include="*.json" .

# Unvalidated args flowing to dangerous operations
grep -rniE --exclude-dir=node_modules --exclude-dir=.git '(args\.\w+|arguments\.\w+)' --include="*.ts" --include="*.js" . | grep -E "(exec|execSync|spawn|readFile|writeFile|query|SQL|eval)"
```

**Severity**: CRITICAL if unvalidated args flow to exec/SQL/filesystem. HIGH if tools exist without inputSchema. MEDIUM if schemas lack constraints (no maxLength, no enum). PASS if all tools have strict schemas.

**Auto-fix**: Offer to add zod schema stubs to tool definitions.

---

#### Check 20: Tool Response Sanitization

**Only in MCP Server Mode.**

Verify tool handlers do not leak raw errors, stack traces, or internal paths in tool results.

```bash
# Raw error in isError responses
grep -rniE --exclude-dir=node_modules --exclude-dir=.git 'isError.*true' --include="*.ts" --include="*.js" -A3 . | grep -E '(\.stack|\.message|JSON\.stringify\(e|JSON\.stringify\(err|\$\{e\}|\$\{err\})'

# Stack traces in catch blocks returning content
grep -rniE --exclude-dir=node_modules --exclude-dir=.git 'catch\s*\([^)]*\)' --include="*.ts" --include="*.js" -A5 . | grep -E '(\.stack|stacktrace|traceback)'

# Full error serialization
grep -rniE --exclude-dir=node_modules --exclude-dir=.git 'JSON\.stringify\((e|err|error)\b' --include="*.ts" --include="*.js" .

# Python traceback in tool returns
grep -rniE --exclude-dir=node_modules --exclude-dir=.git 'traceback\.format_exc\(\)|str\(e\)' --include="*.py" .
```

**Severity**: MEDIUM for stack traces or raw error objects in tool responses. Same criteria as Check 8.

---

#### Check 21: CORS / Origin Validation

**Only in MCP Server Mode + HTTP transport detected.**

```bash
# Dangerous CORS: wildcard origin
grep -rniE --exclude-dir=node_modules --exclude-dir=.git 'cors\(\s*\)|cors\(\s*\{\s*origin\s*:\s*["'"'"']\*["'"'"']|cors\(\s*\{\s*origin\s*:\s*true' --include="*.ts" --include="*.js" .

# Wildcard Access-Control-Allow-Origin header
grep -rniE --exclude-dir=node_modules --exclude-dir=.git 'Access-Control-Allow-Origin.*\*' --include="*.ts" --include="*.js" .

# Python FastAPI wildcard
grep -rniE --exclude-dir=node_modules --exclude-dir=.git 'allow_origins\s*=\s*\["?\*"?\]' --include="*.py" .

# credentials paired with wildcard origin escalates to CRITICAL
grep -rniE --exclude-dir=node_modules --exclude-dir=.git 'credentials\s*:\s*true|Access-Control-Allow-Credentials' --include="*.ts" --include="*.js" .

# PASS indicators: SDK built-in protections
grep -rnE --exclude-dir=node_modules --exclude-dir=.git "hostHeaderValidation|localhostHostValidation|createMcpExpressApp" --include="*.ts" --include="*.js" .
```

**Severity**: CRITICAL if `origin: '*'` combined with `credentials: true`. HIGH for `origin: '*'` on HTTP MCP server. N/A for stdio-only.

---

#### Check 22: MCP Supply Chain & Config Hygiene

**Applies to both MCP Server Mode and Consumer Mode.**

```bash
# @latest floating versions in MCP config (rug-pull risk); @latest is a version SUFFIX (pkg@latest), never a standalone quoted string
grep -rniE --exclude-dir=node_modules --exclude-dir=.git '@latest' . --include=".mcp.json" --include="claude_desktop_config.json" 2>/dev/null

# npx -y without pinned version (auto-install from potentially poisoned package)
grep -rniE --exclude-dir=node_modules --exclude-dir=.git 'npx.*-y' . --include=".mcp.json" --include="claude_desktop_config.json" 2>/dev/null | grep -vE '@[0-9]'

# Lockfile check
ls package-lock.json yarn.lock pnpm-lock.yaml bun.lock bun.lockb 2>/dev/null | grep -q . && echo "HAS_LOCKFILE" || echo "NO_LOCKFILE"

# files whitelist in package.json (if published MCP server)
node -e "const p=require('./package.json'); console.log(p.files ? 'HAS_FILES_WHITELIST' : 'NO_FILES_WHITELIST');" 2>/dev/null

# Shell metacharacters in MCP config args (command injection via config; -A8 covers multi-line arrays)
grep -rniE --exclude-dir=node_modules --exclude-dir=.git -A8 '"args"\s*:\s*\[' . --include=".mcp.json" --include="claude_desktop_config.json" 2>/dev/null | grep -E '[;|&\$\`]'
```

**Severity**: HIGH for `@latest` in MCP config. HIGH for `npx -y` without a pinned `@version`. HIGH for no lockfile. HIGH for shell metacharacters in args arrays. MEDIUM for no files whitelist on published MCP server. PASS if pinned and locked.

**Auto-fix**: Offer to pin all @latest references to current resolved version numbers.

---

#### Check 23: Audit Logging

**Only in MCP Server Mode.**

Verify tool invocations are logged with structured data.

```bash
# Check for structured logging library
grep -rnE --exclude-dir=node_modules --exclude-dir=.git "winston|pino|bunyan|log4js|structlog|logging\.getLogger" . --include="package.json" --include="requirements.txt" 2>/dev/null

# Check for MCP logging notifications
grep -rnE --exclude-dir=node_modules --exclude-dir=.git "sendLoggingMessage|LoggingMessageNotification|setLoggingLevel|notifications/message" --include="*.ts" --include="*.js" .

# Check for observability integration
grep -rnE --exclude-dir=node_modules --exclude-dir=.git "opentelemetry|datadog|sentry|splunk|elastic-apm" . --include="package.json" 2>/dev/null
```

Compare: count tool registrations (`server.tool` / `@mcp.tool`) vs structured logging references. If tools > 0 and structured logging = 0, flag it.

**Severity**: MEDIUM if MCP server has tool handlers but no structured logging. LOW if has logging but no observability integration. PASS if structured logging with audit trail.

---

#### Check 24: Rug-Pull & Tool Mutation Defense

**Applies to MCP Consumer Mode (config files present).**

Check for floating version references that enable rug-pull attacks.

```bash
# @latest in any MCP config (suffix form pkg@latest — do NOT require surrounding quotes)
grep -rniE --exclude-dir=node_modules --exclude-dir=.git '@latest' . --include=".mcp.json" --include="claude_desktop_config.json" 2>/dev/null

# npx without pinned version in MCP config commands
grep -rniE --exclude-dir=node_modules --exclude-dir=.git '"command"\s*:\s*"npx"' . --include=".mcp.json" --include="claude_desktop_config.json" 2>/dev/null

# Verify packages have pinned versions (not @latest)
grep -rniE --exclude-dir=node_modules --exclude-dir=.git '@[a-z0-9-]+/[a-z0-9-]+' . --include=".mcp.json" --include="claude_desktop_config.json" 2>/dev/null | grep -v '@[0-9]' | grep -v '@latest'

# Check if any MCP server hashes tool definitions (integrity verification)
grep -rnE --exclude-dir=node_modules --exclude-dir=.git "createHash|sha256|sha-256|integrity|checksum" --include="*.ts" --include="*.js" . | grep -iE "(tool|description|schema)"
```

**Severity**: HIGH for `@latest` floating versions. MEDIUM for unpinned packages without `@latest`. LOW if no hash/integrity verification for tool definitions (informational). PASS if all pinned with lockfile.

**Auto-fix**: Offer to pin all @latest references to current version numbers.

---

### Step 3 — Report Findings

Output a markdown table:

```
| # | Check | Status | Findings |
|---|-------|--------|----------|
| 1 | Exposed API Keys | PASS/CRITICAL/HIGH/MEDIUM/LOW/N/A | Details... |
| 2 | Rate Limiting | ... | ... |
| ... | ... | ... | ... |
```

For MCP projects, split into two tables: **Core Checks** (1-12) and **MCP-Specific Checks** (13-24).

MCP checks show N/A if project is not an MCP project.

Then list specific findings with file paths and line numbers.

### Step 4 — Offer Fixes

For each finding that has an auto-fixable solution, offer to fix it:
- Missing .gitignore patterns → offer to add them
- Missing SECURITY.md → offer to create one
- Missing dependabot.yml → offer to create one
- execSync with string concat → offer to replace with execFileSync
- Missing input validation → offer to add validation functions
- `jwt.decode` used as verification → offer to replace with `jwt.verify`
- Missing ownership scoping on record access → offer to add userId predicate to the query
- Missing CSRF protection on cookie sessions → offer to add SameSite=Lax/Strict cookie config plus a maintained double-submit lib (csrf-csrf) or the framework built-in (csurf is deprecated — detect it, don't recommend it)
- Missing security headers → offer to add helmet
- Sensitive values in log calls → offer to add redaction (pino redact / sanitize helper)

**MCP-specific fixes:**
- Pinning @latest versions → offer to look up current versions and pin them
- Missing DNS rebinding protection → offer to add hostHeaderValidation middleware
- Missing inputSchema → offer to add zod schema to tool definitions
- Hardcoded secrets in .mcp.json → offer to move to environment variable references
- HTTP without auth → offer to add bearer token auth middleware
- MCP config tracked in git → offer to add to .gitignore

Ask the user before making any changes.
