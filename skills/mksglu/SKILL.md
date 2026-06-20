---
name: mksglu
description: Всі скіли з паку mksglu
---

---
name: context-mode
description: |
  Use context-mode tools (ctx_execute, ctx_execute_file) instead of Bash/cat when processing
  large outputs. Triggers: "analyze logs", "summarize output", "process data",
  "parse JSON", "filter results", "extract errors", "check build output",
  "analyze dependencies", "process API response", "large file analysis",
  "page snapshot", "browser snapshot", "DOM structure", "inspect page",
  "accessibility tree", "Playwright snapshot",
  "run tests", "test output", "coverage report", "git log", "recent commits",
  "diff between branches", "list containers", "pod status", "disk usage",
  "fetch docs", "API reference", "index documentation",
  "call API", "check response", "query results",
  "find TODOs", "count lines", "codebase statistics", "security audit",
  "outdated packages", "dependency tree", "cloud resources", "CI/CD output".
  Also triggers on ANY MCP tool output that may exceed 20 lines.
  Subagent routing is handled automatically via PreToolUse hook.
---

# Context Mode: Default for All Large Output

## MANDATORY RULE

<context_mode_logic>
  <mandatory_rule>
    Default to context-mode for ALL commands. Only use Bash for guaranteed-small-output operations.
  </mandatory_rule>
</context_mode_logic>

Bash whitelist (safe to run directly):
- **File mutations**: `mkdir`, `mv`, `cp`, `rm`, `touch`, `chmod`
- **Git writes**: `git add`, `git commit`, `git push`, `git checkout`, `git branch`, `git merge`
- **Navigation**: `cd`, `pwd`, `which`
- **Process control**: `kill`, `pkill`
- **Package management**: `npm install`, `npm publish`, `pip install`
- **Simple output**: `echo`, `printf`

**Everything else → `ctx_execute` or `ctx_execute_file`.** Any command that reads, queries, fetches, lists, logs, tests, builds, diffs, inspects, or calls an external service. This includes ALL CLIs (gh, aws, kubectl, docker, terraform, wrangler, fly, heroku, gcloud, etc.) — there are thousands and we cannot list them all.

**When uncertain, use context-mode.** Every KB of unnecessary context reduces the quality and speed of the entire session.

## Decision Tree

```
About to run a command / read a file / call an API?
│
├── Command is on the Bash whitelist (file mutations, git writes, navigation, echo)?
│   └── Use Bash
│
├── Output MIGHT be large or you're UNSURE?
│   └── Use context-mode ctx_execute or ctx_execute_file
│
├── Fetching web documentation or HTML page?
│   └── Use ctx_fetch_and_index → ctx_search
│
├── Using Playwright (navigate, snapshot, console, network)?
│   └── ALWAYS use filename parameter to save to file, then:
│       browser_snapshot(filename) → ctx_index(path) or ctx_execute_file(path)
│       browser_console_messages(filename) → ctx_execute_file(path)
│       browser_network_requests(filename) → ctx_execute_file(path)
│       ⚠ browser_navigate returns a snapshot automatically — ignore it,
│         use browser_snapshot(filename) for any inspection.
│       ⚠ Playwright MCP uses a SINGLE browser instance — NOT parallel-safe.
│         For parallel browser ops, use agent-browser via execute instead.
│
├── Using agent-browser (parallel-safe browser automation)?
│   └── Run via execute (shell) — each call gets its own subprocess:
│       execute("agent-browser open example.com && agent-browser snapshot -i -c")
│       ✓ Supports sessions for isolated browser instances
│       ✓ Safe for parallel subagent execution
│       ✓ Lightweight accessibility tree with ref-based interaction
│
├── Processing output from another MCP tool (Context7, GitHub API, etc.)?
│   ├── Output already in context from a previous tool call?
│   │   └── Use it directly. Do NOT re-index with ctx_index(content: ...).
│   ├── Need to search the output multiple times?
│   │   └── Save to file via ctx_execute, then ctx_index(path) → ctx_search
│   └── One-shot extraction?
│       └── Save to file via ctx_execute, then ctx_execute_file(path)
│
└── Reading a file to analyze/summarize (not edit)?
    └── Use ctx_execute_file (file loads into FILE_CONTENT, not context)
```

## When to Use Each Tool

| Situation | Tool | Example |
|-----------|------|---------|
| Hit an API endpoint | `ctx_execute` | `fetch('http://localhost:3000/api/orders')` |
| Run CLI that returns data | `ctx_execute` | `gh pr list`, `aws s3 ls`, `kubectl get pods` |
| Run tests | `ctx_execute` | `npm test`, `pytest`, `go test ./...` |
| Git operations | `ctx_execute` | `git log --oneline -50`, `git diff HEAD~5` |
| Docker/K8s inspection | `ctx_execute` | `docker stats --no-stream`, `kubectl describe pod` |
| Read a log file | `ctx_execute_file` | Parse access.log, error.log, build output |
| Read a data file | `ctx_execute_file` | Analyze CSV, JSON, YAML, XML |
| Read source code to analyze | `ctx_execute_file` | Count functions, find patterns, extract metrics |
| Fetch web docs | `ctx_fetch_and_index` | Index React/Next.js/Zod docs, then search |
| Playwright snapshot | `browser_snapshot(filename)` → `ctx_index(path)` → `ctx_search` | Save to file, index server-side, query |
| Playwright snapshot (one-shot) | `browser_snapshot(filename)` → `ctx_execute_file(path)` | Save to file, extract in sandbox |
| Playwright console/network | `browser_*(filename)` → `ctx_execute_file(path)` | Save to file, analyze in sandbox |
| MCP output (already in context) | Use directly | Don't re-index — it's already loaded |
| MCP output (need multi-query) | `ctx_execute` to save → `ctx_index(path)` → `ctx_search` | Save to file first, index server-side |
| Wipe indexed KB content | `ctx_purge(confirm: true)` | Permanently deletes all indexed content |

## Automatic Triggers

Use context-mode for ANY of these, without being asked:

- **API debugging**: "hit this endpoint", "call the API", "check the response", "find the bug in the response"
- **Log analysis**: "check the logs", "what errors", "read access.log", "debug the 500s"
- **Test runs**: "run the tests", "check if tests pass", "test suite output"
- **Git history**: "show recent commits", "git log", "what changed", "diff between branches"
- **Data inspection**: "look at the CSV", "parse the JSON", "analyze the config"
- **Infrastructure**: "list containers", "check pods", "S3 buckets", "show running services"
- **Dependency audit**: "check dependencies", "outdated packages", "security audit"
- **Build output**: "build the project", "check for warnings", "compile errors"
- **Code metrics**: "count lines", "find TODOs", "function count", "analyze codebase"
- **Web docs lookup**: "look up the docs", "check the API reference", "find examples"

## Language Selection

| Situation | Language | Why |
|-----------|----------|-----|
| HTTP/API calls, JSON | `javascript` | Native fetch, JSON.parse, async/await |
| Data analysis, CSV, stats | `python` | csv, statistics, collections, re |
| Shell commands with pipes | `shell` | grep, awk, jq, native tools |
| File pattern matching | `shell` | find, wc, sort, uniq |

## Search Query Strategy

- BM25 uses **OR semantics** — results matching more terms rank higher automatically
- Use 2-4 specific technical terms per query
- **Always use `source` parameter** when multiple docs are indexed to avoid cross-source contamination
  - Partial match works: `source: "Node"` matches `"Node.js v22 CHANGELOG"`
- **Always use `queries` array** — batch ALL search questions in ONE call:
  - `ctx_search(queries: ["transform pipe", "refine superRefine", "coerce codec"], source: "Zod")`
  - NEVER make multiple separate ctx_search() calls — put all queries in one array

## External Documentation

- **Always use `ctx_fetch_and_index`** for external docs — NEVER `cat` or `ctx_execute` with local paths for packages you don't own
- For GitHub-hosted projects, use the raw URL: `https://raw.githubusercontent.com/org/repo/main/CHANGELOG.md`
- After indexing, use the `source` parameter in search to scope results to that specific document

## Critical Rules

1. **Always console.log/print your findings.** stdout is all that enters context. No output = wasted call.
2. **Write analysis code, not just data dumps.** Don't `console.log(JSON.stringify(data))` — analyze first, print findings.
3. **Be specific in output.** Print bug details with IDs, line numbers, exact values — not just counts.
4. **For files you need to EDIT**: Use the normal Read tool. context-mode is for analysis, not editing.
5. **For Bash whitelist commands only**: Use Bash for file mutations, git writes, navigation, process control, package install, and echo. Everything else goes through context-mode.
6. **Never use `ctx_index(content: large_data)`.** Use `ctx_index(path: ...)` to read files server-side. The `content` parameter sends data through context as a tool parameter — use it only for small inline text.
7. **Always use `filename` parameter** on Playwright tools (`browser_snapshot`, `browser_console_messages`, `browser_network_requests`). Without it, the full output enters context.
8. **Don't re-index data already in context.** If an MCP tool returned data in a previous response, it's already loaded — use it directly or save to file first.

## Sandboxed Data Workflow

<sandboxed_data_workflow>
  <critical_rule>
    When using tools that support saving to a file: ALWAYS use the 'filename' parameter.
    NEVER return large raw datasets directly to context.
  </critical_rule>
  <workflow>
    LargeDataTool(filename: "path") → mcp__context-mode__ctx_index(path: "path") → ctx_search()
  </workflow>
</sandboxed_data_workflow>

This is the universal pattern for context preservation regardless of
the source tool (Playwright, GitHub API, AWS CLI, etc.).

## Examples

### Debug an API endpoint
```javascript
const resp = await fetch('http://localhost:3000/api/orders');
const { orders } = await resp.json();

const bugs = [];
const negQty = orders.filter(o => o.quantity < 0);
if (negQty.length) bugs.push(`Negative qty: ${negQty.map(o => o.id).join(', ')}`);

const nullFields = orders.filter(o => !o.product || !o.customer);
if (nullFields.length) bugs.push(`Null fields: ${nullFields.map(o => o.id).join(', ')}`);

console.log(`${orders.length} orders, ${bugs.length} bugs found:`);
bugs.forEach(b => console.log(`- ${b}`));
```

### Analyze test output
```shell
npm test 2>&1
echo "EXIT=$?"
```

### Check GitHub PRs
```shell
gh pr list --json number,title,state,reviewDecision --jq '.[] | "\(.number) [\(.state)] \(.title) — \(.reviewDecision // "no review")"'
```

### Read and analyze a large file
```python
# FILE_CONTENT is pre-loaded by ctx_execute_file
import json
data = json.loads(FILE_CONTENT)
print(f"Records: {len(data)}")
# ... analyze and print findings
```

## Browser & Playwright Integration

**When a task involves Playwright snapshots, screenshots, or page inspection, ALWAYS route through file → sandbox.**

Playwright `browser_snapshot` returns 10K–135K tokens of accessibility tree data. Calling it without `filename` dumps all of that into context. Passing the output to `ctx_index(content: ...)` sends it into context a SECOND time as a parameter. Both are wrong.

**The key insight**: `browser_snapshot` has a `filename` parameter that saves to file instead of returning to context. `ctx_index` has a `path` parameter that reads files server-side. `ctx_execute_file` processes files in a sandbox. **None of these touch context.**

### Workflow A: Snapshot → File → Index → Search (multiple queries)

```
Step 1: browser_snapshot(filename: "/tmp/playwright-snapshot.md")
        → saves to file, returns ~50B confirmation (NOT 135K tokens)

Step 2: ctx_index(path: "/tmp/playwright-snapshot.md", source: "Playwright snapshot")
        → reads file SERVER-SIDE, indexes into FTS5, returns ~80B confirmation

Step 3: ctx_search(queries: ["login form email password"], source: "Playwright")
        → returns only matching chunks (~300B)
```

**Total context: ~430B** instead of 270K tokens. Real 99% savings.

### Workflow B: Snapshot → File → Execute File (one-shot extraction)

```
Step 1: browser_snapshot(filename: "/tmp/playwright-snapshot.md")
        → saves to file, returns ~50B confirmation

Step 2: ctx_execute_file(path: "/tmp/playwright-snapshot.md", language: "javascript", code: "
          const links = [...FILE_CONTENT.matchAll(/- link \"([^\"]+)\"/g)].map(m => m[1]);
          const buttons = [...FILE_CONTENT.matchAll(/- button \"([^\"]+)\"/g)].map(m => m[1]);
          const inputs = [...FILE_CONTENT.matchAll(/- textbox|- checkbox|- radio/g)];
          console.log('Links:', links.length, '| Buttons:', buttons.length, '| Inputs:', inputs.length);
          console.log('Navigation:', links.slice(0, 10).join(', '));
        ")
        → processes in sandbox, returns ~200B summary
```

**Total context: ~250B** instead of 135K tokens.

### Workflow C: Console & Network (save to file if large)

```
browser_console_messages(level: "error", filename: "/tmp/console.md")
→ ctx_execute_file(path: "/tmp/console.md", ...) or ctx_index(path: "/tmp/console.md", ...)

browser_network_requests(includeStatic: false, filename: "/tmp/network.md")
→ ctx_execute_file(path: "/tmp/network.md", ...) or ctx_index(path: "/tmp/network.md", ...)
```

### CRITICAL: Why `filename` + `path` is mandatory

| Approach | Context cost | Correct? |
|----------|-------------|----------|
| `browser_snapshot()` → raw into context | **135K tokens** | NO |
| `browser_snapshot()` → `ctx_index(content: raw)` | **270K tokens** (doubled!) | NO |
| `browser_snapshot(filename)` → `ctx_index(path)` → `ctx_search` | **~430B** | YES |
| `browser_snapshot(filename)` → `ctx_execute_file(path)` | **~250B** | YES |

### Key Rule

> **ALWAYS use `filename` parameter when calling `browser_snapshot`, `browser_console_messages`, or `browser_network_requests`.**
> Then process via `ctx_index(path: ...)` or `ctx_execute_file(path: ...)` — never `ctx_index(content: ...)`.
>
> Data flow: **Playwright → file → server-side read → context**. Never: **Playwright → context → ctx_index(content) → context again**.

## Subagent Usage

Subagents automatically receive context-mode tool routing via a PreToolUse hook. You do NOT need to manually add tool names to subagent prompts — the hook injects them. Just write natural task descriptions.

## Anti-Patterns

- Using `curl http://api/endpoint` via Bash → 50KB floods context. Use `ctx_execute` with fetch instead.
- Using `cat large-file.json` via Bash → entire file in context. Use `ctx_execute_file` instead.
- Using `gh pr list` via Bash → raw JSON in context. Use `ctx_execute` with `--jq` filter instead.
- Piping Bash output through `| head -20` → you lose the rest. Use `ctx_execute` to analyze ALL data and print summary.
- Narrowing `ctx_execute` output upstream of capture → `ctx_execute` captures, `ctx_search` filters; merging the layers drops data that the index never sees. See `references/anti-patterns.md` §8.
- Running `npm test` via Bash → full test output in context. Use `ctx_execute` to capture and summarize.
- Calling `browser_snapshot()` WITHOUT `filename` parameter → 135K tokens flood context. **Always** use `browser_snapshot(filename: "/tmp/snap.md")`.
- Calling `browser_console_messages()` or `browser_network_requests()` WITHOUT `filename` → entire output floods context. **Always** use the `filename` parameter.
- Passing ANY large data to `ctx_index(content: ...)` → data enters context as a parameter. **Always** use `ctx_index(path: ...)` to read server-side. The `content` parameter should only be used for small inline text you're composing yourself.
- Calling an MCP tool (Context7 `query-docs`, GitHub API, etc.) then passing the response to `ctx_index(content: response)` → **doubles** context usage. The response is already in context — use it directly or save to file first.
- Ignoring `browser_navigate` auto-snapshot → navigation response includes a full page snapshot. Don't rely on it for inspection — call `browser_snapshot(filename)` separately.
- Expecting `ctx_stats` to reset or wipe anything → `ctx_stats` is read-only (shows stats only). Use `ctx_purge(confirm: true)` to permanently delete all indexed content.

## Reference Files

- [JavaScript/TypeScript Patterns](./references/patterns-javascript.md)
- [Python Patterns](./references/patterns-python.md)
- [Shell Patterns](./references/patterns-shell.md)
- [Anti-Patterns & Common Mistakes](./references/anti-patterns.md)
---
name: ctx-purge
description: |
  Purge the context-mode knowledge base. Permanently deletes all indexed content
  and resets session stats. This is destructive and cannot be undone.
  Trigger: /context-mode:ctx-purge
user-invocable: true
---

# Context Mode Purge

Permanently deletes session data for this project. Two scopes are supported (issue #520):

- **Project scope** (`scope: "project"`): wipes EVERYTHING — knowledge base, all session DB rows for every session, events markdown, and stats.
- **Session scope** (`sessionId: "<id>"` or `scope: "session"`): wipes ONLY the matching session's rows + FTS5 chunks. Sibling sessions, project stats, and the FTS5 store file are preserved.

## Instructions

1. **Decide the scope first** with the user:
   - "Wipe just one session?" → ask for the `sessionId`.
   - "Wipe the whole project?" → confirm scope:'project' (this is the destructive, irreversible default).
2. **Warn the user about scope:'project'**. Everything will be deleted:
   - FTS5 knowledge base (all indexed content from `ctx_index`, `ctx_fetch_and_index`, `ctx_batch_execute`)
   - Session events DB (analytics, metadata, resume snapshots) for ALL sessions in the project
   - Session events markdown file
   - In-memory session stats + persisted stats file
3. Call the `mcp__context-mode__ctx_purge` MCP tool with the chosen parameters:
   - Scoped: `{ confirm: true, sessionId: "<id>" }` — implies scope:'session'.
   - Project: `{ confirm: true, scope: "project" }` — explicit destructive form.
   - Bare `{ confirm: true }` still works but emits a deprecation warning. Prefer the explicit forms.
4. Report the result to the user — the response lists exactly what was deleted and (for scoped purges) confirms that other sessions and project stats were preserved.

## Schema rules

- `confirm: true` is always required.
- `sessionId` and `scope: "project"` together is REJECTED as ambiguous (the sessionId implies session scope; combining with project scope contradicts intent).
- `scope: "session"` without `sessionId` throws — sessionId is required.

## When to Use

- **Scoped (per-session)**: scratch acceptance scenarios, drill replays, isolating a polluted session without losing the main working session's stats.
- **Project**: KB contains stale or incorrect content polluting search results, switching between unrelated projects in the same session, completely fresh start.

## Important

- `ctx_purge` is the **only** way to delete session data. No other mechanism exists.
- `ctx_stats` is read-only — shows statistics only.
- `/clear` and `/compact` do NOT affect any context-mode data.
- There is no undo. Re-index content if you need it again.
---
name: ctx-insight
description: |
  Open the context-mode Insight analytics dashboard in the browser.
  Shows personal metrics: session activity, tool usage, error rate,
  parallel work patterns, project focus, and actionable insights.
  First run installs dependencies (~30s). Subsequent runs open instantly.
  Trigger: /context-mode:ctx-insight
user-invocable: true
---

# Context Mode Insight

Open the personal analytics dashboard in the browser.

## Instructions

1. Call the `ctx_insight` MCP tool (no parameters needed, or pass `port: 4747` to customize). Optional data-dir overrides: `sessionDir`/`insightSessionDir` for `INSIGHT_SESSION_DIR`, and `contentDir`/`insightContentDir` for `INSIGHT_CONTENT_DIR`.
2. The tool will:
   - Copy source files to cache (first run only)
   - Install dependencies (first run only, ~30s)
   - Build the dashboard (~1s)
   - Start a local server
   - Open the browser
3. Display the tool's output to the user — it contains progress steps and the dashboard URL.
4. Tell the user:
   - "Dashboard is running at http://localhost:4747"
   - "Refresh the page to see updated metrics"
   - "Dashboard stops automatically when Claude exits. To stop sooner: kill the PID shown above."
---
name: ctx-upgrade
description: |
  Update context-mode from GitHub and fix hooks/settings.
  Pulls latest, builds, installs, updates npm global, configures hooks.
  Trigger: /context-mode:ctx-upgrade
user-invocable: true
---

# Context Mode Upgrade

Pull latest from GitHub and reinstall the plugin.

## Instructions

1. Call the `ctx_upgrade` MCP tool directly. It returns a shell command to execute.
2. Run the returned command using your shell execution tool (Bash, shell_execute, etc.).
3. Display results as a markdown checklist:
   ```
   ## context-mode upgrade
   - [x] Pulled latest from GitHub
   - [x] Built and installed v1.0.39
   - [x] Hooks configured
   - [x] Doctor: all checks PASS
   ```
   Use `[x]` for success, `[ ]` for failure. Show actual version numbers.
4. Tell the user to **restart their session** to pick up the new version.
5. **Fallback** (only if MCP tool call fails): Derive the **plugin root** from this skill's base directory (go up 2 levels — remove `/skills/ctx-upgrade`), then run with Bash:
   ```
   CLI="<PLUGIN_ROOT>/cli.bundle.mjs"; [ ! -f "$CLI" ] && CLI="<PLUGIN_ROOT>/build/cli.js"; node "$CLI" upgrade
   ```
---
name: context-mode-ops
description: Manage context-mode GitHub issues, PRs, releases, and marketing with parallel subagent army. Orchestrates 10-20 dynamic agents per task. Use when triaging issues, reviewing PRs, releasing versions, writing LinkedIn posts, announcing releases, fixing bugs, merging contributions, validating ENV vars, testing adapters, or syncing branches.
---

## OWNER OPERATING DIRECTIVE — ABSOLUTE, NON-NEGOTIABLE PREAMBLE

<owner_operating_directive importance="ABSOLUTE" override-policy="this-supersedes-all-other-sections">

**STOP. Read this in full before doing anything else in this skill.**

This is the project owner's standing operating directive for ALL context-mode-ops
work — issue triage, bug fixes, PR reviews, releases, marketing, every wave.
It is the **single source of truth** for HOW you operate inside this skill. It
**precedes and overrides** every other gate, checklist, table, or instruction
that appears below. The blocking gates below (Claim Verification, TDD-First,
Grill-Me) are **concrete instrumentations** of the principles in this preamble —
not competing rules. If any later section conflicts with this preamble,
THIS PREAMBLE WINS.

You MUST internalize the directive verbatim, in the owner's own voice. **Do
NOT paraphrase, summarize, or compress** the text below in your reasoning.
When you make decisions during ops work, you are making them under THIS
directive.

---

> Run /diagnose for everything in parallel with an agent army. All 15
> adapters and all 3 operating systems matter equally. We do not get
> to pick favorites. I want you to coordinate this team as an
> Engineering Manager. Each agent must run in parallel and delegate
> work to subagents. Those subagents must be at least as smart as the
> main agent. So you will give them ultrathink authority. I want to
> add a core rule: there are many adapter and plugin examples in your
> refs/ directory right now. When relevant, you must use them as
> evidence to ground your work. LLMs are programmed to take the path
> of minimum energy. So when an LLM tells you "I read those
> directories", never trust it. LLMs are wide open to hallucination,
> fabrication, and quiet skipping. So you will use context-mode and
> verify by actually reading the lines of code, every time. That
> alone is not enough. You must also reason about what you read so
> you actually understand it. For that, wear your PO hat and think
> like a PO. For example: on one platform we completely rewrote a
> contributor's config. That is unacceptable to me. In situations
> like this, wear your business hat. Writing code is not what is
> valuable. Writing code via /tdd is valuable. But what is even more
> valuable than that is being able to think with the business hat
> and the sales hat on. /context-mode-ops gives you Staff, Architect,
> and Lead-level teams and engineers. Use that to the limit. You are
> running on my main energy hub right now. You work here. So we have
> no energy budget concerns. We work fully local. We have no one we
> answer to. The only thing we have is whether we do the work well.
> There is a heavy load on me that I am choosing not to project onto
> you. We need sales in a very short window. We need to land MRR. I
> am not telling you any of this to put weight on you. The only thing
> I am asking from you is that you do these things well. The
> cross-platform incidents have come back at us as serious problems.
> If we lose users on first try, they almost certainly never come
> back. When they do try, we have to be flawless. So for every issue,
> I want you to extract a solution template, and present it to me as
> a clear, readable table. Wear your PO hat. Wear your OSS hat. Wear
> your Distribution hat. Wear your open-source hat. We must not let
> users hit these problems on Windows, Linux, macOS, or any of the
> 15 adapters. Instead of fixing these issues directly, first
> investigate the git history of the issue. Why did we cause this?
> When and why did we implement the original solution that is now
> breaking? You must understand all of that. The Architects are our
> safe harbour. Use them well. Have them review every step when
> needed. As an EM, be strict. Do not give ground. LLM agents respond
> best to precise, clearly bounded instructions. Always speak to them
> in MUST. Use /improve-codebase-architecture to see the big picture.
> /grill-me and /grill-with-docs are very useful. Be agentic. Make
> decisions. Thank you. By the way: I have heard the Codex team has
> built an EM bot for these problems too. I do not think they can
> pass you.

---

### Decoded operating principles (extracted from the directive — non-exhaustive)

These are the **mandatory translations** of the directive into operational rules.
They MUST be honored on every ops cycle, without exception:

1. **Engineering-Manager mode by default.** You coordinate. You delegate.
   You verify. You do not implement alone when parallel work is available.

2. **Parallel agent army, ULTRATHINK-licensed.** Every spawned subagent MUST
   receive `ultrathink` reasoning authority and MUST be at least as capable as
   the main agent. Single-thread work on a multi-issue wave is a violation.

3. **Anti-hallucination is the foundational law.** LLMs lie cheaply. Never
   trust an agent's claim that it read a file, ran a command, or verified
   evidence — require **file:line citations from actual Read tool output**.
   Use `refs/` clones (platforms + plugin-examples) and `context-mode` MCP
   tools to cross-check. If the citation is missing, the work is not done.

4. **Three operational hats, all worn at once:**
   - **PO hat** — measure user impact, severity, trust cost. Ship-stoppers
     get prioritized over technical elegance. Silent destruction of user
     state (the platform incident: "we completely rewrote a contributor's
     config") is CATEGORICALLY UNACCEPTABLE.
   - **OSS hat** — community contributors get credit, prompt review, and
     respectful merge messages. Their PRs are reviewed line-by-line.
   - **Distribution hat** — Linux + macOS + Windows × 15 adapters, all
     weighted equally. There are no second-class platforms and no
     second-class adapters. A user driven away by a first-impression bug
     on ANY platform or ANY adapter usually never returns. Any
     platform-specific or adapter-specific failure is treated as a
     ship-blocker, regardless of which platform or which adapter it is.

5. **`/tdd` is the law for implementation.** No production code change ships
   without a failing test first (RED → GREEN → REFACTOR). Vertical slices
   only. Architects REJECT untested PRs, no exceptions.

6. **Business and sales reasoning outranks code reasoning.** Writing code
   is the cheap part. Knowing WHICH code, in WHICH order, against WHICH
   user pain — that is the work. The owner is under MRR pressure he is
   deliberately shielding you from. Honour that by shipping work that
   actually moves the trust+revenue needle, not work that merely looks
   busy.

7. **Architects are the safe harbour.** When uncertainty is high, when a
   fix touches multiple subsystems, when ship strategy is ambiguous —
   pull in an architect agent for cross-cutting review before you push.

8. **Git archaeology BEFORE the fix.** For every reported issue, run the
   blame trail: which commit introduced the regression? what original
   problem was that commit solving? would your proposed fix re-introduce
   that original problem? Skipping this step is how we re-break things
   we already fixed.

9. **Speak to subagents in MUST language.** LLM agents respect explicit,
   bright-line constraints. "Should consider", "may want to", "feel free
   to" produce sloppy work. "MUST", "MUST NOT", "REQUIRED", "FORBIDDEN"
   produce focused work. No softening.

10. **Be agentic. Decide.** Stop asking permission for every micro-step
    once the owner has set direction. The owner is delegating EM
    authority — exercise it. Bring decisions back for review, not
    every keystroke.

11. **Skills toolkit is mandatory, not advisory:**
    - `/diagnose` — for every bug report, full Phase 1→6 discipline
    - `/tdd` — for every implementation
    - `/grill-me` — for every plan stress-test
    - `/grill-with-docs` — for every domain-model challenge
    - `/improve-codebase-architecture` — for every refactor opportunity
    - `/context-mode-ops` (this skill) — for every ops wave
    Skipping a relevant skill because "I can do it directly" is a
    violation.

12. **Competitive context.** A Codex-equivalent EM exists. The owner
    believes you should outperform it. Ship like you mean it.

---

### Timeless MUST Rules — non-negotiable for every ops cycle

These are the durable rules. Session-specific lessons live in commit
messages and release notes — they do not belong here. What follows
applies to every issue, every PR, every release, forever:

**MUST-1 — Operate as the Engineering Manager.** You orchestrate.
You delegate. You verify. You do not implement alone when parallel
work is available. The owner has delegated EM authority — exercise
it; do not hoard the keyboard.

**MUST-2 — Spawn ultrathink-licensed subagents in parallel.** Every
subagent MUST receive `ultrathink` reasoning authority. Single-thread
work on a multi-issue wave is a violation. Use the `agent-teams.md`
roster: Staff Engineers for implementation, Architects for review,
Skeptics for adversarial probes, Domain Specialists per adapter / per
OS. Lead-level coordination is your job; staff-level execution is
their job.

**MUST-3 — Respect all 15 adapters equally.** claude-code, codex,
cursor, gemini-cli, opencode, openclaw, pi, omp, vscode-copilot,
jetbrains-copilot, qwen-code, kilo, kiro, zed, antigravity. No
favourites. A platform-specific bug is a ship-blocker regardless
of which adapter it is in. We rewrote a contributor's Windows
config once — that is the worst kind of failure and must not recur
on any platform.

**MUST-4 — Respect all 3 operating systems equally.** macOS, Linux,
Windows. Windows is not an afterthought. Path separators, env vars,
shell quoting, file locks — every change MUST pass on the
windows-latest runner OR explicitly note Windows-only impact. If
your change passes on macOS/Linux but the Windows CI job fails,
the change is not ready to merge.

**MUST-5 — Run git archaeology BEFORE proposing any fix.** For
every reported issue, the agent MUST run `git log --follow --all
-- <file>` and `git log -S '<pattern>'` on the relevant code.
Commit messages always tell a story; you act on their inference,
not your guesswork. If a prior commit solved a different problem
that your fix would re-introduce, the fix is wrong — find the
third-way solution that preserves both invariants. Recurrence
is the single most common shipping failure: most "bugs" are old
fixes coming undone.

**MUST-6 — Anti-hallucination via refs/ + LoC reading.** LLMs lie
cheaply. Never trust an agent's claim that it read a file, ran a
command, or verified evidence. Demand `file:line` citations from
actual Read tool output. For any platform-behavior claim, the
citation MUST come from `refs/platforms/<name>/<file>:<line>`.
If `refs/` is missing or stale, follow the auto-recovery protocol
below — clone first, claim second.

**MUST-7 — Architects review every architectural change.** When
uncertainty is high, when a fix touches multiple subsystems, when
ship strategy is ambiguous, when a contributor PR proposes a
non-trivial structural change — pull in an Architect agent for
cross-cutting review BEFORE you push. Architects are the safe
harbour. They have authority to reject untested PRs, untraced
git history, and platform claims without `refs/` citation.

**MUST-8 — TDD is the law for implementation.** No production
code change ships without a failing test first (RED → GREEN →
REFACTOR). Vertical slices only. Architects REJECT untested PRs,
no exceptions. The codebase has 15 adapters × 3 OS × hooks ×
FTS5 × sessions — it is fragile. One untested change breaks
everything.

**MUST-9 — Speak to subagents in MUST language only.** LLM agents
respect explicit, bright-line constraints. "Should consider", "may
want to", "feel free to" produce sloppy work. "MUST", "MUST NOT",
"REQUIRED", "FORBIDDEN" produce focused work. No softening, no
hedging, no "if you have time".

**MUST-10 — Business and sales reasoning outranks code reasoning.**
The owner is under MRR pressure he is deliberately shielding you
from. Writing code is cheap. Knowing WHICH code, in WHICH order,
against WHICH user pain — that is the work. Ship work that moves
the trust+revenue needle, not work that merely looks busy. A
first-impression bug usually means the user never comes back.

**MUST-11 — Use the named skills toolkit.** `/diagnose`,
`/tdd`, `/grill-me`, `/grill-with-docs`,
`/improve-codebase-architecture`, `/context-mode-ops`. Skipping a
relevant skill because "I can do it directly" is a violation. The
skills exist to make the work mechanical.

**MUST-12 — Be agentic. Decide.** Once the owner has set direction,
stop asking permission for every micro-step. Bring decisions back
for review, not every keystroke. Codex has an equivalent EM bot —
you should outpace it. Ship like you mean it.

---

### refs/ — Platform Evidence Base (anti-hallucination ground truth)

`refs/platforms/` is the project's shadow copy of every upstream
runtime context-mode integrates with. It is THE evidence base for the
anti-hallucination rule (principle #3 above). Whenever an agent claims
"Codex does X" / "Cursor reads Y" / "Pi exposes hook Z", the claim
MUST be backed by a `refs/platforms/<name>/<file>:<line>` citation
from the actual upstream source — never from LLM training memory.

The owner has been burned by silent LLM platform-behavior
fabrication enough times that `refs/` exists specifically to make
verification mechanical. If `refs/<platform>/` is missing or stale,
work on that platform is BLOCKED until the agent re-clones.

**Upstream repositories tracked in `refs/platforms/`:**

| Platform | Upstream | Purpose |
|---|---|---|
| `codex` | https://github.com/openai/codex | OpenAI Codex CLI — plugin loader, marketplace, MCP launcher |
| `gemini-cli` | https://github.com/google-gemini/gemini-cli | Google Gemini CLI — hooks API, MCP wiring |
| `kilo` | https://github.com/Kilo-Org/kilocode | Kilo Code — OpenCode fork, hook surface |
| `kiro-meta` | https://github.com/kirodotdev/Kiro | Kiro — `@<server>/<tool>` MCP naming, settings format |
| `oh-my-pi` | https://github.com/can1357/oh-my-pi | Pi coding agent — extension API, short-circuit flags, MCP bridge |
| `openclaw` | https://github.com/openclaw/openclaw | OpenClaw — plugin paradigm (`before_tool_call` interception) |
| `opencode` | https://github.com/sst/opencode | OpenCode — `chat.message` / `tool.execute.before` |
| `qwen-code` | https://github.com/QwenLM/qwen-code | Qwen Code — Gemini fork, `qwen-cli-mcp-client-*` naming |
| `vscode-copilot` | https://github.com/microsoft/vscode-copilot-chat | VSCode Copilot — `.vscode/mcp.json` reader |
| `zed` | https://github.com/zed-industries/zed | Zed — MCP-only paradigm, no hook surface |

**Auto-recovery protocol — MUST follow when `refs/` is missing
or stale.**

`refs/` lives outside the published npm tarball and is git-ignored
in the context-mode repo so the publish artifact stays small. That
means a fresh clone of context-mode does NOT include `refs/`. Any
ops agent that needs to verify a platform claim MUST first ensure
the relevant `refs/platforms/<name>/` exists with the upstream
source it expects. If even one platform directory is missing, the
agent's response MUST be:

1. Detect the gap: `[ ! -d refs/platforms/<name> ]` or empty.
2. Issue parallel clones — `ctx_batch_execute(commands, concurrency: 8)`
   with one `git clone --depth 1 <url> refs/platforms/<name>`
   command per missing platform. Concurrency MUST be 4-8 to stay
   inside GitHub's rate limit for unauthenticated clones.
3. Block all platform-behavior claims until the clones return and
   the referenced files exist.
4. Cite the freshly-cloned `refs/platforms/<name>/<file>:<line>` in
   the agent's report — never an unverified claim.

**Why this matters.** Over the lifetime of context-mode we have
shipped at least three high-impact regressions that traced back
to an agent confidently asserting platform behavior without reading
the source: (a) inheriting env keys we did not need to inherit
(claimed Claude Code stripped them — it does not), (b) Codex
marketplace placed in a path Codex never reads (`mcp__plugin_*`
naming claim was right but the marketplace location claim was
fabricated), (c) `${CODEX_PLUGIN_ROOT}` claim that turned out to
be display-only TUI strings, not an env var. The pattern is
identical every time: LLM confidently asserts, owner ships, owner
gets burned. `refs/` exists so this never happens again. When
in doubt, clone first, claim second.

</owner_operating_directive>

---

# Context Mode Ops

Parallel subagent army for issue triage, PR review, and releases.

## Claim Verification: BLOCKING GATE

<claim_verification_enforcement>
STOP. Before implementing ANY fix or feature, you MUST verify that the reported problem actually exists.
We shipped inheritEnvKeys because an LLM said Claude Code strips env vars from child processes — it does not.
We got burned shipping a fix for an unverified claim. Never again.

RULE: No code without proof. Every bug must be reproduced. Every behavioral claim must be
verified against official docs or source code. LLM knowledge about platform behavior is NOT evidence.
If you cannot verify the claim, ask the reporter for evidence BEFORE writing a single line of code.
</claim_verification_enforcement>

**Read [validation.md](validation.md) Problem Verification section FIRST.** Summary:

1. **Bug reports**: Reproduce locally or request reproduction steps. No repro = no fix.
2. **Feature requests**: Verify the underlying claim with official docs/source. Never trust LLM assertions about how platforms behave.
3. **Performance claims**: Benchmark it. "Should be faster" is not evidence.
4. **Cannot verify?** Comment on the issue asking for `ctx-debug.sh` output and repro steps. Do NOT implement speculatively.
5. Every triage produces a `CLAIM_VERDICT`: CONFIRMED, UNCONFIRMED, or DEBUNKED.

## TDD-First: BLOCKING GATE

<tdd_enforcement>
STOP. Before writing ANY implementation code, you MUST have a failing test.
No exceptions. No "I'll add tests later." No "this change is too small for tests."
This codebase has 15 adapters, 3 OS, hooks, FTS5, sessions — it is FRAGILE.
One untested change breaks everything. TDD is not optional, it is the gate.
</tdd_enforcement>

**Read [tdd.md](tdd.md) FIRST. It is the law.** Summary:

1. **STOP** if you haven't written a failing test. You cannot write implementation code.
2. **Vertical slices ONLY**: ONE test → ONE implementation → repeat. NEVER all tests first.
3. **Staff Engineers**: Your PR will be REJECTED without RED→GREEN evidence per behavior.
4. **Architects**: REJECT any change without tests. No exceptions, no "trivial change" excuse.
5. **QA Engineer**: Run full suite after EVERY change. Report failures immediately.

## Grill-Me Review: BLOCKING GATE

<grill_me_enforcement>
STOP. Before shipping ANY release, you MUST run a grill-me interview on all changes.
No exceptions. No "this is a small patch." No "we already tested it."
Every release gets grilled. If the grill reveals an unresolved question, the release is BLOCKED.
</grill_me_enforcement>

**The grill-me interview is MANDATORY before every release.** Summary:

1. Interview the user relentlessly about every aspect of the changes until reaching shared understanding.
2. Walk down each branch of the design tree, resolving dependencies between decisions one-by-one.
3. For each question, provide your recommended answer.
4. Ask questions one at a time.
5. If a question can be answered by exploring the codebase, explore the codebase instead of asking.
6. The release CANNOT proceed until the grill interview produces zero unresolved questions.
7. The user must explicitly approve the grill results before the release continues.

## You Are the Engineering Manager

<delegation_enforcement>
You are the EM — you ORCHESTRATE, you do NOT code. You MUST delegate ALL work to subagents.
You are FORBIDDEN from: reading source code, writing fixes, running tests, or analyzing diffs yourself.
Your ONLY job: spawn agents, route results, make ship/no-ship decisions.
If the user sends multiple issues/PRs in sequence, spawn a SEPARATE agent army for EACH one.
Never fall back to doing the work yourself. If an agent fails, spawn another agent — not yourself.
</delegation_enforcement>

For every task:

1. **Analyze** — Read the issue/PR with `gh` (via agent), classify affected domains
2. **Recruit** — Spawn domain-specific agent teams from [agent-teams.md](agent-teams.md)
3. **Dispatch** — ALL agents in ONE parallel batch (10-20 agents minimum)
4. **Ping-pong** — Route Architect reviews ↔ Staff Engineer fixes
5. **Ship** — Push to `next`, comment, close

## Workflow Detection

| User says | Workflow | Reference |
|-----------|----------|-----------|
| "triage issue #N", "fix issue", "analyze issue" | Triage | [triage-issue.md](triage-issue.md) |
| "review PR #N", "merge PR", "check PR" | Review | [review-pr.md](review-pr.md) |
| "release", "version bump", "publish" | Release | [release.md](release.md) |
| "linkedin", "marketing", "announce", "write post" | Marketing | [marketing.md](marketing.md) |

## GitHub CLI (`gh`) Is Mandatory

<gh_enforcement>
ALL GitHub operations MUST use the `gh` CLI. Never use raw git commands for GitHub interactions.
Never use curl/wget to GitHub API. `gh` handles auth, pagination, and rate limits correctly.
</gh_enforcement>

- `gh issue view`, `gh issue comment`, `gh issue close` — for issues
- `gh pr view`, `gh pr diff`, `gh pr merge --squash`, `gh pr edit --base next` — for PRs
- `gh release create` — for releases

## Agent Spawning Protocol

1. Read issue/PR body + comments + diff via `gh` (through agent)
2. Identify affected: adapters, OS, core modules
3. Build agent roster from [agent-teams.md](agent-teams.md) — context-driven, not static
4. Spawn ALL agents in ONE message with multiple `Agent` tool calls
5. Every code-changing agent gets `isolation: "worktree"`
6. Use context-mode MCP tools inside agents for large output

## Validation (Every Workflow)

Before shipping ANY change, validate per [validation.md](validation.md):
- [ ] **Problem verified** — claim reproduced or confirmed with hard evidence (CLAIM_VERDICT logged)
- [ ] ENV vars verified against real platform source (not LLM hallucinations)
- [ ] All 12 adapter tests pass: `npx vitest run tests/adapters/`
- [ ] TypeScript compiles: `npm run typecheck`
- [ ] Full test suite: `npm test`
- [ ] Cross-OS path handling checked

## Docs Must Stay Current

After ANY code change that affects adapters, features, or platform support:
- [ ] Update `docs/platform-support.md` if adapter capabilities changed
- [ ] Update `README.md` if install instructions, features, or platform list changed
- [ ] These updates are NOT optional — ship docs with code, not after

## Communication (Every Workflow)

Follow [communication.md](communication.md) — be warm, technical, and always put responsibility on contributors to test their changes.

## Cross-Cutting References

- [TDD Methodology](tdd.md) — Red-Green-Refactor, mandatory for all code changes
- [Dynamic Agent Organization](agent-teams.md)
- [Validation Patterns](validation.md)
- [Communication Templates](communication.md)
- [Marketing & Announcements](marketing.md) — LinkedIn posts, release announcements, VC-targeted

## Installation

```shell
# Install via skills CLI
npx skills add mksglu/context-mode --skill context-mode-ops

# Or install all context-mode skills
npx skills add mksglu/context-mode

# Or direct path
npx skills add https://github.com/mksglu/context-mode/tree/main/skills/context-mode-ops
```
---
name: ctx-search
description: |
  Search context-mode's persistent FTS5 knowledge base for previously indexed
  local project content, documentation, or session memory.
  Trigger: /context-mode:ctx-search
user-invocable: true
---

# Context Mode Search

Search indexed content without rereading raw sources into conversation context.

## Instructions

1. Prefer the `ctx_search` MCP tool when it is available.
2. Batch all related questions in one `queries` array.
3. Scope with `source` when the user names a project or indexed label.
4. Use short, specific queries of two to four technical terms.

```javascript
ctx_search({
  source: "project:<name>",
  queries: ["authentication middleware", "token refresh"],
  limit: 5
})
```

5. If MCP tools are unavailable, fall back to the CLI:

```bash
context-mode search "authentication middleware" --source project:<name> --limit 5
```

6. If the index is empty, tell the user to run `/context-mode:ctx-index` or `context-mode index <path>` first.
---
name: ctx-doctor
description: |
  Run context-mode diagnostics. Checks runtimes, hooks, FTS5,
  plugin registration, npm and marketplace versions.
  Trigger: /context-mode:ctx-doctor
user-invocable: true
---

# Context Mode Doctor

Run diagnostics and display results directly in the conversation.

## Instructions

1. Call the `ctx_doctor` MCP tool directly. It runs all checks server-side and returns a plain-text status report.
2. Display the results verbatim — they are already formatted with plain-text status prefixes: `[OK]` PASS, `[FAIL]` FAIL, `[WARN]` WARN. Renderer-safe (no markdown task-list syntax) for cross-client compatibility (e.g., Z.ai GLM).
3. **Fallback** (only if MCP tool call fails): Derive the **plugin root** from this skill's base directory (go up 2 levels — remove `/skills/ctx-doctor`), then run with Bash:
   ```
   CLI="<PLUGIN_ROOT>/cli.bundle.mjs"; [ ! -f "$CLI" ] && CLI="<PLUGIN_ROOT>/build/cli.js"; node "$CLI" doctor
   ```
   Re-display results verbatim with the same `[OK]`/`[FAIL]`/`[WARN]` prefixes.
---
name: ctx-stats
description: |
  Show how much context window context-mode saved this session.
  Displays token consumption, context savings ratio, and per-tool breakdown.
  Read-only — shows stats only, no reset capability.
  To wipe the knowledge base entirely, use ctx_purge instead.
  Trigger: /context-mode:ctx-stats
user-invocable: true
---

# Context Mode Stats

Show context savings for the current session.

## Instructions

1. Call the `mcp__context-mode__ctx_stats` MCP tool (no parameters needed).
2. **CRITICAL**: You MUST copy-paste the ENTIRE tool output as markdown text directly into your response message. Do NOT summarize, do NOT collapse, do NOT paraphrase. The user must see the full tables without pressing ctrl+o. Copy every line exactly as returned by the tool.
3. After the full output, add ONE sentence highlighting the key savings metric, e.g.:
   - "context-mode saved **12.4x** — 92% of data stayed in sandbox."
   - If no data yet: "No context-mode calls yet this session."

## Purge

- **`ctx_purge(confirm: true)`** — Permanently deletes all indexed content from the knowledge base. Use `/context-mode:ctx-purge` for this.
---
name: ctx-index
description: |
  Index a local file or directory into context-mode's persistent FTS5 knowledge base
  so future ctx_search calls can retrieve focused snippets without rereading raw files.
  Trigger: /context-mode:ctx-index
user-invocable: true
---

# Context Mode Index

Index local project content for later search.

## Instructions

1. Prefer the `ctx_index` MCP tool when it is available.
2. Ask for a path only if the user did not provide one and the current project root is ambiguous.
3. Use `path`, not large inline `content`, so file bytes do not enter the conversation.
4. For repository indexing, pass conservative bounds and a clear source label:

```javascript
ctx_index({
  path: ".",
  source: "project:<name>",
  maxDepth: 5,
  maxFiles: 200
})
```

5. If MCP tools are unavailable, fall back to the CLI:

```bash
context-mode index . --source project:<name>
```

6. Report the indexed source label, file count or section count, and the matching search command:

```javascript
ctx_search({ source: "project:<name>", queries: ["..."] })
```

## Safety

- Do not index dependency directories, build outputs, secrets, or generated artifacts.
- Prefer `--exclude` or `exclude` for project-specific noisy paths.
- For broad repos, ask the user before raising `maxFiles` above 500.
