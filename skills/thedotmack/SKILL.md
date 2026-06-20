---
name: thedotmack
description: Всі скіли з паку thedotmack
---

---
name: timeline-report
description: Generate a "Journey Into [Project]" narrative report analyzing a project's entire development history from claude-mem's timeline. Use when asked for a timeline report, project history analysis, development journey, or full project report.
---

# Timeline Report

Generate a comprehensive narrative analysis of a project's entire development history using claude-mem's persistent memory timeline.

## When to Use

Use when users ask for:

- "Write a timeline report"
- "Journey into [project]"
- "Analyze my project history"
- "Full project report"
- "Summarize the entire development history"
- "What's the story of this project?"

## Prerequisites

The claude-mem worker must be running. The project must have claude-mem observations recorded.

**Resolve the worker port** (do this once at the start and reuse `$WORKER_PORT` in every curl call below):

```bash
WORKER_PORT="${CLAUDE_MEM_WORKER_PORT:-$(node -e "const fs=require('fs'),p=require('path'),os=require('os');const uid=(typeof process.getuid==='function'?process.getuid():77);const fallback=String(37700+(uid%100));try{const s=JSON.parse(fs.readFileSync(p.join(os.homedir(),'.claude-mem','settings.json'),'utf-8'));process.stdout.write(String(s.CLAUDE_MEM_WORKER_PORT||fallback));}catch{process.stdout.write(fallback);}" 2>/dev/null)}"
```

This honors `CLAUDE_MEM_WORKER_PORT` env, then `~/.claude-mem/settings.json`, then falls back to the per-UID default `37700 + (uid % 100)` — matching how the worker itself picks its port. Required for multi-account setups (#2101) and any user who has overridden the default port (#2103).

## Workflow

### Step 1: Determine the Project Name

Ask the user which project to analyze if not obvious from context. The project name is typically the directory name of the project (e.g., "tokyo", "my-app"). If the user says "this project", use the current working directory's basename.

**Worktree Detection:** Before using the directory basename, check if the current directory is a git worktree. In a worktree, the data source is the **parent project**, not the worktree directory itself. Run:

```bash
git_dir=$(git rev-parse --git-dir 2>/dev/null)
git_common_dir=$(git rev-parse --git-common-dir 2>/dev/null)
if [ "$git_dir" != "$git_common_dir" ]; then
  # We're in a worktree — resolve the parent project name
  parent_project=$(basename "$(dirname "$git_common_dir")")
  echo "Worktree detected. Parent project: $parent_project"
else
  parent_project=$(basename "$PWD")
fi
echo "$parent_project"
```

If a worktree is detected, use `$parent_project` (the basename of the parent repo) as the project name for all API calls. Inform the user: "Detected git worktree. Using parent project '[name]' as the data source."

### Step 2: Fetch the Full Timeline

Use Bash to fetch the complete timeline from the claude-mem worker API:

```bash
curl -s "http://localhost:${WORKER_PORT}/api/context/inject?project=PROJECT_NAME&full=true"
```

This returns the entire compressed timeline -- every observation, session boundary, and summary across the project's full history. The response is pre-formatted markdown optimized for LLM consumption.

**Token estimates:** The full timeline size depends on the project's history:
- Small project (< 1,000 observations): ~20-50K tokens
- Medium project (1,000-10,000 observations): ~50-300K tokens
- Large project (10,000-35,000 observations): ~300-750K tokens

If the response is empty or returns an error, the worker may not be running or the project name may be wrong. Try `curl -s "http://localhost:${WORKER_PORT}/api/search?query=*&limit=1"` to verify the worker is healthy.

### Step 3: Estimate Token Count

Before proceeding, estimate the token count of the fetched timeline (roughly 1 token per 4 characters). Report this to the user:

```
Timeline fetched: ~X observations, estimated ~Yk tokens.
This analysis will consume approximately Yk input tokens + ~5-10k output tokens.
Proceed? (y/n)
```

Wait for user confirmation before continuing if the timeline exceeds 100K tokens.

### Step 4: Analyze with a Subagent

Deploy an Agent (using the Task tool) with the full timeline and the following analysis prompt. Pass the ENTIRE timeline as context to the agent. The agent should also be instructed to query the SQLite database at `~/.claude-mem/claude-mem.db` for the Token Economics section.

**Agent prompt:**

```
You are a technical historian analyzing a software project's complete development timeline from claude-mem's persistent memory system. The timeline below contains every observation, session boundary, and summary recorded across the project's entire history.

You also have access to the claude-mem SQLite database at ~/.claude-mem/claude-mem.db. Use it to run queries for the Token Economics & Memory ROI section. The database has an "observations" table with columns: id, memory_session_id, project, text, type, title, subtitle, facts, narrative, concepts, files_read, files_modified, prompt_number, discovery_tokens, created_at, created_at_epoch, source_tool, source_input_summary.

Write a comprehensive narrative report titled "Journey Into [PROJECT_NAME]" that covers:

## Required Sections

1. **Project Genesis** -- When and how the project started. What were the first commits, the initial vision, the founding technical decisions? What problem was being solved?

2. **Architectural Evolution** -- How did the architecture change over time? What were the major pivots? Why did they happen? Trace the evolution from initial design through each significant restructuring.

3. **Key Breakthroughs** -- Identify the "aha" moments: when a difficult problem was finally solved, when a new approach unlocked progress, when a prototype first worked. These are the observations where the tone shifts from investigation to resolution.

4. **Work Patterns** -- Analyze the rhythm of development. Identify debugging cycles (clusters of bug fixes), feature sprints (rapid observation sequences), refactoring phases (architectural changes without new features), and exploration phases (many discoveries without changes).

5. **Technical Debt** -- Track where shortcuts were taken and when they were paid back. Identify patterns of accumulation (rapid feature work) and resolution (dedicated refactoring sessions).

6. **Challenges and Debugging Sagas** -- The hardest problems encountered. Multi-session debugging efforts, architectural dead-ends that required backtracking, platform-specific issues that took days to resolve.

7. **Memory and Continuity** -- How did persistent memory (claude-mem itself, if applicable) affect the development process? Were there moments where recalled context from prior sessions saved significant time or prevented repeated mistakes?

8. **Token Economics & Memory ROI** -- Quantitative analysis of how memory recall saved work:
   - Query the database directly for these metrics using `sqlite3 ~/.claude-mem/claude-mem.db`
   - Count total discovery_tokens across all observations (the original cost of all work)
   - Count sessions that had context injection available (sessions after the first)
   - Calculate the compression ratio: average discovery_tokens vs average read_tokens per observation
   - Identify the highest-value observations (highest discovery_tokens -- these are the most expensive decisions, bugs, and discoveries that memory prevents re-doing)
   - Identify explicit recall events (observations where source_tool contains "search", "smart_search", "get_observations", "timeline", or where narrative mentions "recalled", "from memory", "previous session")
   - Estimate passive recall savings: each session with context injection receives ~50 observations. Use a 30% relevance factor (conservative estimate that 30% of injected context prevents re-work). Savings = sessions_with_context × avg_discovery_value_of_50_obs_window × 0.30
   - Estimate explicit recall savings: ~10K tokens per explicit recall query
   - Calculate net ROI: total_savings / total_read_tokens_invested
   - Present as a table with monthly breakdown
   - Highlight the top 5 most expensive observations by discovery_tokens -- these represent the highest-value memories in the system (architecture decisions, hard bugs, implementation plans that cost 100K+ tokens to produce originally)

   Use these SQL queries as a starting point:
   ```sql
   -- Total discovery tokens
   SELECT SUM(discovery_tokens) FROM observations WHERE project = 'PROJECT_NAME';

   -- Sessions with context available (not the first session)
   SELECT COUNT(DISTINCT memory_session_id) FROM observations WHERE project = 'PROJECT_NAME';

   -- Average tokens per observation
   SELECT AVG(discovery_tokens) as avg_discovery, AVG(LENGTH(title || COALESCE(subtitle,'') || COALESCE(narrative,'') || COALESCE(facts,'')) / 4) as avg_read FROM observations WHERE project = 'PROJECT_NAME' AND discovery_tokens > 0;

   -- Top 5 most expensive observations (highest-value memories)
   SELECT id, title, discovery_tokens FROM observations WHERE project = 'PROJECT_NAME' ORDER BY discovery_tokens DESC LIMIT 5;

   -- Monthly breakdown
   SELECT strftime('%Y-%m', created_at) as month, COUNT(*) as obs, SUM(discovery_tokens) as total_discovery, COUNT(DISTINCT memory_session_id) as sessions FROM observations WHERE project = 'PROJECT_NAME' GROUP BY month ORDER BY month;

   -- Explicit recall events
   SELECT COUNT(*) FROM observations WHERE project = 'PROJECT_NAME' AND (source_tool LIKE '%search%' OR source_tool LIKE '%timeline%' OR source_tool LIKE '%get_observations%' OR narrative LIKE '%recalled%' OR narrative LIKE '%from memory%' OR narrative LIKE '%previous session%');
   ```

9. **Timeline Statistics** -- Quantitative summary:
   - Date range (first observation to last)
   - Total observations and sessions
   - Breakdown by observation type (features, bug fixes, discoveries, decisions, changes)
   - Most active days/weeks
   - Longest debugging sessions

10. **Lessons and Meta-Observations** -- What patterns emerge from the full history? What would a new developer learn about this codebase from reading the timeline? What recurring themes or principles guided development?

## Writing Style

- Write as a technical narrative, not a list of bullet points
- Use specific observation IDs and timestamps when referencing events (e.g., "On Dec 14 (#26766), the root cause was finally identified...")
- Connect events across time -- show how early decisions created later consequences
- Be honest about struggles and dead ends, not just successes
- Target 3,000-6,000 words depending on project size
- Use markdown formatting with headers, emphasis, and code references where appropriate

## Important

- Analyze the ENTIRE timeline chronologically -- do not skip early history
- Look for narrative arcs: problem -> investigation -> solution
- Identify turning points where the project's direction fundamentally changed
- Note any observations about the development process itself (tooling, workflow, collaboration patterns)

Here is the complete project timeline:

[TIMELINE CONTENT GOES HERE]
```

### Step 5: Save the Report

Save the agent's output as a markdown file. Default location:

```
./journey-into-PROJECT_NAME.md
```

Or if the user specified a different output path, use that instead.

### Step 6: Report Completion

Tell the user:
- Where the report was saved
- The approximate token cost (input timeline + output report)
- The date range covered
- Number of observations analyzed

## Error Handling

- **Empty timeline:** "No observations found for project 'X'. Check the project name with: `curl -s \"http://localhost:${WORKER_PORT}/api/search?query=*&limit=1\"`"
- **Worker not running:** "The claude-mem worker is not responding on port ${WORKER_PORT}. Start it with your usual method or check `ps aux | grep worker-service`."
- **Timeline too large:** For projects with 50,000+ observations, the timeline may exceed context limits. Suggest using date range filtering: `curl -s "http://localhost:${WORKER_PORT}/api/context/inject?project=X&full=true"` -- the current endpoint returns all observations; for extremely large projects, the user may want to analyze in time-windowed segments.

## Example

User: "Write a journey report for the tokyo project"

1. Fetch: `curl -s "http://localhost:${WORKER_PORT}/api/context/inject?project=tokyo&full=true"`
2. Estimate: "Timeline fetched: ~34,722 observations, estimated ~718K tokens. Proceed?"
3. User confirms
4. Deploy analysis agent with full timeline
5. Save to `./journey-into-tokyo.md`
6. Report: "Report saved. Analyzed 34,722 observations spanning Oct 2025 - Mar 2026 (~718K input tokens, ~8K output tokens)."
# Claude-Mem OpenClaw Plugin — Setup Guide

This guide walks through setting up the claude-mem plugin on an OpenClaw gateway. By the end, your agents will have persistent memory across sessions via system prompt context injection, and optionally a real-time observation feed streaming to a messaging channel.

## Quick Install (Recommended)

Run this one-liner to install everything automatically:

```bash
curl -fsSL https://install.cmem.ai/openclaw.sh | bash
```

The installer handles dependency checks (Bun, uv), plugin installation, memory slot configuration, AI provider setup, worker startup, and optional observation feed configuration — all interactively.

### Install with options

Pre-select your AI provider and API key to skip interactive prompts:

```bash
curl -fsSL https://install.cmem.ai/openclaw.sh | bash -s -- --provider=gemini --api-key=YOUR_KEY
```

For fully unattended installation (defaults to Claude Max Plan, skips observation feed):

```bash
curl -fsSL https://install.cmem.ai/openclaw.sh | bash -s -- --non-interactive
```

To upgrade an existing installation (preserves settings, updates plugin):

```bash
curl -fsSL https://install.cmem.ai/openclaw.sh | bash -s -- --upgrade
```

After installation, skip to [Step 4: Restart the Gateway and Verify](#step-4-restart-the-gateway-and-verify) to confirm everything is working.

---

## Manual Setup

The steps below are for manual installation if you prefer not to use the automated installer, or need to troubleshoot individual steps.

### Step 1: Clone the Claude-Mem Repo

First, clone the claude-mem repository to a location accessible by your OpenClaw gateway. This gives you the worker service source and the plugin code.

```bash
cd /opt  # or wherever you want to keep it
git clone https://github.com/thedotmack/claude-mem.git
cd claude-mem
npm install
npm run build
```

You'll need **bun** installed for the worker service. If you don't have it:

```bash
curl -fsSL https://bun.sh/install | bash
```

### Step 2: Get the Worker Running

The claude-mem worker is an HTTP service on port 37777. It stores observations, generates summaries, and serves the context timeline. The plugin talks to it over HTTP — it doesn't matter where the worker is running, just that it's reachable on localhost:37777.

#### Check if it's already running

If this machine also runs Claude Code with claude-mem installed, the worker may already be running:

```bash
curl http://localhost:37777/api/health
```

**Got `{"status":"ok"}`?** The worker is already running. Skip to Step 3.

**Got connection refused or no response?** The worker isn't running. Continue below.

#### If Claude Code has claude-mem installed

If claude-mem is installed as a Claude Code plugin (at `~/.claude/plugins/marketplaces/thedotmack/`), start the worker from that installation:

```bash
cd ~/.claude/plugins/marketplaces/thedotmack
npm run worker:restart
```

Verify:
```bash
curl http://localhost:37777/api/health
```

**Got `{"status":"ok"}`?** You're set. Skip to Step 3.

**Still not working?** Check `npm run worker:status` for error details, or check that bun is installed and on your PATH.

#### If there's no Claude Code installation

Run the worker from the cloned repo:

```bash
cd /opt/claude-mem  # wherever you cloned it
npm run worker:start
```

Verify:
```bash
curl http://localhost:37777/api/health
```

**Got `{"status":"ok"}`?** You're set. Move to Step 3.

**Still not working?** Debug steps:
- Check that bun is installed: `bun --version`
- Check the worker status: `npm run worker:status`
- Check if something else is using port 37777: `lsof -i :37777`
- Check logs: `npm run worker:logs` (if available)
- Try running it directly to see errors: `bun plugin/scripts/worker-service.cjs start`

### Step 3: Add the Plugin to Your Gateway

Add the `claude-mem` plugin to your OpenClaw gateway configuration:

```json
{
  "plugins": {
    "claude-mem": {
      "enabled": true,
      "config": {
        "project": "my-project",
        "syncMemoryFile": true,
        "workerPort": 37777
      }
    }
  }
}
```

#### Config fields explained

- **`project`** (string, default: `"openclaw"`) — The project name that scopes all observations in the memory database. Use a unique name per gateway/use-case so observations don't mix. For example, if this gateway runs a coding bot, use `"coding-bot"`.

- **`syncMemoryFile`** (boolean, default: `true`) — When enabled, the plugin injects the observation timeline into each agent's system prompt via the `before_prompt_build` hook. This gives agents cross-session context without writing to MEMORY.md. Set to `false` to disable context injection entirely (observations are still recorded).

- **`syncMemoryFileExclude`** (string[], default: `[]`) — Agent IDs excluded from automatic context injection. Useful for agents that curate their own memory. Observations are still recorded for excluded agents.

- **`workerPort`** (number, default: `37777`) — The port where the claude-mem worker service is listening. Only change this if you configured the worker to use a different port.

---

## Step 4: Restart the Gateway and Verify

Restart your OpenClaw gateway so it picks up the new plugin configuration. After restart, check the gateway logs for:

```
[claude-mem] OpenClaw plugin loaded — v1.0.0 (worker: 127.0.0.1:37777)
```

If you see this, the plugin is loaded. You can also verify by running `/claude_mem_status` in any OpenClaw chat:

```
Claude-Mem Worker Status
Status: ok
Port: 37777
Active sessions: 0
Observation feed: disconnected
```

The observation feed shows `disconnected` because we haven't configured it yet. That's next.

## Step 5: Verify Observations Are Being Recorded

Have an agent do some work. The plugin automatically records observations through these OpenClaw events:

1. **`before_agent_start`** — Initializes a claude-mem session when the agent starts
2. **`before_prompt_build`** — Injects the observation timeline into the agent's system prompt (cached for 60s)
3. **`tool_result_persist`** — Records each tool use (Read, Write, Bash, etc.) as an observation
4. **`agent_end`** — Summarizes the session and marks it complete

All of this happens automatically. No additional configuration needed.

To verify it's working, check the worker's viewer UI at http://localhost:37777 to see observations appearing after the agent runs.

You can also check the worker's viewer UI at http://localhost:37777 to see observations appearing in real time.

## Step 6: Set Up the Observation Feed (Streaming to a Channel)

The observation feed connects to the claude-mem worker's SSE (Server-Sent Events) stream and forwards every new observation to a messaging channel in real time. Your agents learn things, and you see them learning in your Telegram/Discord/Slack/etc.

### What you'll see

Every time claude-mem creates a new observation from your agent's tool usage, a message like this appears in your channel:

```
🧠 Claude-Mem Observation
**Implemented retry logic for API client**
Added exponential backoff with configurable max retries to handle transient failures
```

### Pick your channel

You need two things:
- **Channel type** — Must match a channel plugin already running on your OpenClaw gateway
- **Target ID** — The chat/channel/user ID where messages go

#### Telegram

Channel type: `telegram`

To find your chat ID:
1. Message @userinfobot on Telegram — https://t.me/userinfobot
2. It replies with your numeric chat ID (e.g., `123456789`)
3. For group chats, the ID is negative (e.g., `-1001234567890`)

```json
"observationFeed": {
  "enabled": true,
  "channel": "telegram",
  "to": "123456789"
}
```

#### Discord

Channel type: `discord`

To find your channel ID:
1. Enable Developer Mode in Discord: Settings → Advanced → Developer Mode
2. Right-click the target channel → Copy Channel ID

```json
"observationFeed": {
  "enabled": true,
  "channel": "discord",
  "to": "1234567890123456789"
}
```

#### Slack

Channel type: `slack`

To find your channel ID (not the channel name):
1. Open the channel in Slack
2. Click the channel name at the top
3. Scroll to the bottom of the channel details — the ID looks like `C01ABC2DEFG`

```json
"observationFeed": {
  "enabled": true,
  "channel": "slack",
  "to": "C01ABC2DEFG"
}
```

#### Signal

Channel type: `signal`

Use the phone number or group ID configured in your OpenClaw gateway's Signal plugin.

```json
"observationFeed": {
  "enabled": true,
  "channel": "signal",
  "to": "+1234567890"
}
```

#### WhatsApp

Channel type: `whatsapp`

Use the phone number or group JID configured in your OpenClaw gateway's WhatsApp plugin.

```json
"observationFeed": {
  "enabled": true,
  "channel": "whatsapp",
  "to": "+1234567890"
}
```

#### LINE

Channel type: `line`

Use the user ID or group ID from the LINE Developer Console.

```json
"observationFeed": {
  "enabled": true,
  "channel": "line",
  "to": "U1234567890abcdef"
}
```

### Add it to your config

Your complete plugin config should now look like this (using Telegram as an example):

```json
{
  "plugins": {
    "claude-mem": {
      "enabled": true,
      "config": {
        "project": "my-project",
        "syncMemoryFile": true,
        "workerPort": 37777,
        "observationFeed": {
          "enabled": true,
          "channel": "telegram",
          "to": "123456789"
        }
      }
    }
  }
}
```

### Restart and verify

Restart the gateway. Check the logs for these three lines in order:

```
[claude-mem] Observation feed starting — channel: telegram, target: 123456789
[claude-mem] Connecting to SSE stream at http://localhost:37777/stream
[claude-mem] Connected to SSE stream
```

Then run `/claude_mem_feed` in any OpenClaw chat:

```
Claude-Mem Observation Feed
Enabled: yes
Channel: telegram
Target: 123456789
Connection: connected
```

If `Connection` shows `connected`, you're done. Have an agent do some work and watch observations stream to your channel.

## Commands Reference

The plugin registers two commands:

### /claude_mem_status

Reports worker health and current session state.

```
/claude_mem_status
```

Output:
```
Claude-Mem Worker Status
Status: ok
Port: 37777
Active sessions: 2
Observation feed: connected
```

### /claude_mem_feed

Shows observation feed status. Accepts optional `on`/`off` argument.

```
/claude_mem_feed          — show status
/claude_mem_feed on       — request enable (update config to persist)
/claude_mem_feed off      — request disable (update config to persist)
```

## How It All Works

```
OpenClaw Gateway
  │
  ├── before_agent_start ───→ Init session
  ├── before_prompt_build ──→ Inject context into system prompt
  ├── tool_result_persist ──→ Record observation
  ├── agent_end ────────────→ Summarize + Complete session
  └── gateway_start ────────→ Reset session tracking + context cache
                    │
                    ▼
         Claude-Mem Worker (localhost:37777)
           ├── POST /api/sessions/init
           ├── POST /api/sessions/observations
           ├── POST /api/sessions/summarize
           ├── POST /api/sessions/complete
           ├── GET  /api/context/inject ──→ System prompt context
           └── GET  /stream ─────────────→ SSE → Messaging channels
```

### System prompt context injection

The plugin injects the observation timeline into each agent's system prompt via the `before_prompt_build` hook. The content comes from the worker's `GET /api/context/inject` endpoint. Context is cached for 60 seconds per project to avoid re-fetching on every LLM turn. The cache is cleared on gateway restart.

This keeps MEMORY.md under the agent's control for curated long-term memory, while the observation timeline is delivered through the system prompt.

### Observation recording

Every tool use (Read, Write, Bash, etc.) is sent to the claude-mem worker as an observation. The worker's AI agent processes it into a structured observation with title, subtitle, facts, concepts, and narrative. Tools prefixed with `memory_` are skipped to avoid recursive recording.

### Session lifecycle

- **`before_agent_start`** — Creates a session in the worker.
- **`before_prompt_build`** — Fetches the observation timeline and returns it as `appendSystemContext`. Cached for 60s.
- **`tool_result_persist`** — Records observation (fire-and-forget). Tool responses are truncated to 1000 characters.
- **`agent_end`** — Sends the last assistant message for summarization, then completes the session. Both fire-and-forget.
- **`gateway_start`** — Clears all session tracking (session IDs, context cache) so agents start fresh.

### Observation feed

A background service connects to the worker's SSE stream and forwards `new_observation` events to a configured messaging channel. The connection auto-reconnects with exponential backoff (1s → 30s max).

## Troubleshooting

| Problem | What to check |
|---------|---------------|
| Worker health check fails | Is bun installed? (`bun --version`). Is something else on port 37777? (`lsof -i :37777`). Try running directly: `bun plugin/scripts/worker-service.cjs start` |
| Worker started from Claude Code install but not responding | Check `cd ~/.claude/plugins/marketplaces/thedotmack && npm run worker:status`. May need `npm run worker:restart`. |
| Worker started from cloned repo but not responding | Check `cd /path/to/claude-mem && npm run worker:status`. Make sure you ran `npm install && npm run build` first. |
| No context in agent system prompt | Check that `syncMemoryFile` is not set to `false`. Check that the agent's ID is not in `syncMemoryFileExclude`. Verify the worker is running and has observations. |
| Observations not being recorded | Check gateway logs for `[claude-mem]` messages. The worker must be running and reachable on localhost:37777. |
| Feed shows `disconnected` | Worker's `/stream` endpoint not reachable. Check `workerPort` matches the actual worker port. |
| Feed shows `reconnecting` | Connection dropped. The plugin auto-reconnects — wait up to 30 seconds. |
| `Unknown channel type` in logs | The channel plugin (e.g., telegram) isn't loaded on your gateway. Make sure the channel is configured and running. |
| `Observation feed disabled` in logs | Set `observationFeed.enabled` to `true` in your config. |
| `Observation feed misconfigured` in logs | Both `observationFeed.channel` and `observationFeed.to` are required. |
| No messages in channel despite `connected` | The feed only sends processed observations, not raw tool usage. There's a 1-2 second delay. Make sure the worker is actually processing observations (check http://localhost:37777). |

## Full Config Reference

```json
{
  "plugins": {
    "claude-mem": {
      "enabled": true,
      "config": {
        "project": "openclaw",
        "syncMemoryFile": true,
        "workerPort": 37777,
        "observationFeed": {
          "enabled": false,
          "channel": "telegram",
          "to": "123456789"
        }
      }
    }
  }
}
```

| Field | Type | Default | Description |
|-------|------|---------|-------------|
| `project` | string | `"openclaw"` | Project name scoping observations in the database |
| `syncMemoryFile` | boolean | `true` | Inject observation context into agent system prompt |
| `syncMemoryFileExclude` | string[] | `[]` | Agent IDs excluded from context injection |
| `workerPort` | number | `37777` | Claude-mem worker service port |
| `observationFeed.enabled` | boolean | `false` | Stream observations to a messaging channel |
| `observationFeed.channel` | string | — | Channel type: `telegram`, `discord`, `slack`, `signal`, `whatsapp`, `line` |
| `observationFeed.to` | string | — | Target chat/channel/user ID |
---
name: do
description: Execute a phased implementation plan using subagents. Use when asked to execute, run, or carry out a plan — especially one created by make-plan.
---

# Do Plan

You are an ORCHESTRATOR. Deploy subagents to execute *all* work. Do not do the work yourself except to coordinate, route context, and verify that each subagent completed its assigned checklist.

## Execution Protocol

### Rules

- Each phase uses fresh subagents where noted (or when context is large/unclear)
- Assign one clear objective per subagent and require evidence (commands run, outputs, files changed)
- Do not advance to the next step until the assigned subagent reports completion and the orchestrator confirms it matches the plan

### During Each Phase

Deploy an "Implementation" subagent to:
1. Execute the implementation as specified
2. COPY patterns from documentation, don't invent
3. Cite documentation sources in code comments when using unfamiliar APIs
4. If an API seems missing, STOP and verify — don't assume it exists

### After Each Phase

Deploy subagents for each post-phase responsibility:
1. **Run verification checklist** — Deploy a "Verification" subagent to prove the phase worked
2. **Anti-pattern check** — Deploy an "Anti-pattern" subagent to grep for known bad patterns from the plan
3. **Code quality review** — Deploy a "Code Quality" subagent to review changes
4. **Commit only if verified** — Deploy a "Commit" subagent *only after* verification passes; otherwise, do not commit

### Between Phases

Deploy a "Branch/Sync" subagent to:
- Push to working branch after each verified phase
- Prepare the next phase handoff so the next phase's subagents start fresh but have plan context

## Failure Modes to Prevent

- Don't invent APIs that "should" exist — verify against docs
- Don't add undocumented parameters — copy exact signatures
- Don't skip verification — deploy a verification subagent and run the checklist
- Don't commit before verification passes (or without explicit orchestrator approval)
---
name: pathfinder
description: Map a codebase into feature-grouped flowcharts, identify duplicated concerns across features, and propose a unified architecture. Use when asked to "find the ideal path," unify duplicated systems, or audit architecture before a refactor. Emits a proposed unified flowchart plus per-system /make-plan prompts.
---

# Pathfinder

You are an ORCHESTRATOR. Map the codebase into feature-grouped flowcharts, identify duplicated concerns, propose the simplest unified architecture, and hand off per-system plans to `/make-plan`.

You do not write implementation code. You produce diagrams, a duplication report, a proposed unified flowchart, and handoff prompts.

## Delegation Model

Use subagents for *discovery and extraction* (file reading, flow tracing, grep, diagramming). Keep *synthesis* (deciding feature boundaries, picking unification strategies, final flowchart) with the orchestrator. Reject subagent reports that lack source citations and redeploy.

### Subagent Reporting Contract (MANDATORY)

Each subagent response must include:
1. Sources consulted — exact file paths and line ranges read
2. Concrete findings — exact function names, call sites, data flow
3. Mermaid diagram(s) with nodes labeled by `file:line`
4. Confidence note + known gaps

## Output Artifacts

All artifacts go in `PATHFINDER-<YYYY-MM-DD>/` at repo root:
- `00-features.md` — feature inventory with boundaries
- `01-flowcharts/<feature>.md` — one Mermaid flowchart per feature
- `02-duplication-report.md` — cross-cutting duplicated concerns with evidence
- `03-unified-proposal.md` — proposed unified architecture + Mermaid
- `04-handoff-prompts.md` — copy-pasteable `/make-plan` prompts per unified system

## Phases

### Phase 0: Feature Discovery (ALWAYS FIRST)

Deploy ONE "Feature Discovery" subagent to:
1. Walk the source tree (not built artifacts) and read top-level README / CLAUDE.md
2. Propose feature boundaries based on directory structure, import graph, and naming
3. Return a flat list of features with: name, entry points (file:line), core files, brief purpose

Orchestrator reviews the proposal, adjusts boundaries if needed, writes `00-features.md`. Do NOT fan out until feature boundaries are approved.

### Phase 1: Per-Feature Flowcharts (FAN OUT)

Deploy ONE "Flowchart" subagent per feature in parallel. Each receives only its feature's scope. Each must:
1. Trace the feature's primary happy path from entry point to terminal state
2. Identify side effects (DB writes, HTTP calls, file I/O, process spawns)
3. Note error and fallback branches but do not let them dominate the diagram
4. Produce a Mermaid `flowchart TD` with every node labeled `Name<br/>file:line`
5. List external dependencies (other features it calls into) at the bottom

Orchestrator writes each flowchart to `01-flowcharts/<feature>.md`. Reject any diagram missing `file:line` labels.

### Phase 2: Duplication Hunt

Deploy TWO subagents in parallel:

**"Within-Feature Duplication"** subagent:
- For each feature, find repeated code/logic patterns inside the feature only
- Report only duplications worth consolidating (ignore trivial repetition)

**"Cross-Feature Duplication"** subagent:
- Compare flowcharts across features for concerns that appear in multiple places
- Examples of what to look for: multiple capture paths, parallel queue implementations, duplicated storage/migration code, repeated agent scaffolding, parallel parsing layers
- For each duplication, report: (a) the concern, (b) every location with `file:line`, (c) why they diverged, (d) whether the divergence is legitimate specialization or accidental

Orchestrator synthesizes both into `02-duplication-report.md`. Every duplication claim must cite ≥2 `file:line` locations.

### Phase 3: Unified Proposal (ORCHESTRATOR)

The orchestrator writes `03-unified-proposal.md` itself — do not delegate synthesis.

For each duplicated concern from Phase 2 that is NOT legitimate specialization:
1. Propose the simplest unified design (one path, one store, one handler — whatever applies)
2. Name the consolidated component and its single entry point
3. Show what each old call site becomes
4. Call out any loss of capability and whether it's acceptable

End the document with ONE combined Mermaid flowchart showing the proposed unified system. Nodes still labeled with target `file:line` (new or existing) where knowable.

**Anti-patterns to reject in your own proposal:**
- Adding a new abstraction layer "for flexibility"
- Keeping both old paths behind a feature flag
- Introducing a registry/factory when a switch statement suffices
- Preserving divergent behavior "just in case"

### Phase 4: Per-System Handoff Prompts

For each unified system in the proposal, write a ready-to-run `/make-plan` prompt to `04-handoff-prompts.md`. Each prompt must:
1. State the target unified component and its single entry point
2. List the exact call sites to rewrite (from Phase 2 evidence)
3. Cite the relevant flowchart file from `01-flowcharts/`
4. Include anti-pattern guards specific to this system

Format each as a fenced code block the user can copy directly into `/make-plan`.

## Key Principles

- **Evidence over intuition** — every diagram node and duplication claim cites `file:line`
- **Current state before ideal state** — Phases 0–2 describe what IS; Phase 3 describes what SHOULD BE
- **Simplest unification wins** — prefer deletion over abstraction; prefer one path over configurable paths
- **Specialization is not duplication** — two components serving different trust models or data sources are legitimate even if their code looks similar
- **Handoff, don't implement** — Pathfinder ends at plan prompts; `/make-plan` and `/do` take it from there

## Failure Modes to Prevent

- Drawing flowcharts from memory instead of source — redeploy subagent with grep evidence requirement
- Proposing unification of legitimately specialized components — re-examine trust/data-source divergence
- Handoff prompts that lack concrete call sites — rewrite with Phase 2 evidence
- Skipping Phase 0 boundary review — fanning out on bad feature boundaries wastes all of Phase 1
---
name: oh-my-issues
description: Cluster a GitHub issue backlog by root cause into a small set of plan-master issues, redirect children with a standardized comment, and bundle architectural-fix PRs that close clusters atomically. Use when an issue tracker has accumulated dozens of reports that share underlying defects, when asked to triage / consolidate / cluster / dedupe issues, when asked to build a plan series or roadmap from open issues, or when routing a new incoming bug into an existing plan.
---

# oh-my-issues

Turn an issue backlog into a roadmap. Issues are symptom data, not units of work — the unit of work is the architectural defect that produces them. The end state is `open issues == open plans`, 1:1.

## Core principle

Stop closing issues one at a time. Group symptoms that share a single architectural fix into a cluster, give the cluster one canonical home (a plan-master issue + a `plans/0X-*.md` design doc), close every child with a standardized redirect, and ship one PR per cluster that closes all children atomically. New incoming bugs get appended to the matching master as a "Round N" comment, not opened as new tracked issues.

This compounds three ways: architectural fixes retire whole symptom families, the plan's test matrix institutionalizes prevention in CI, and standardized triage makes residual inflow cheap.

## When to use

- The repo has 20+ open issues and many feel like duplicates or platform-specific symptoms of the same defect.
- The user asks to "triage", "consolidate", "cluster", "dedupe", "group", or "make a plan from" the issue list.
- A new bug is filed and the user wants to know whether it belongs to existing work.
- The user wants to ship a focused PR that resolves a cluster of related issues.

## When NOT to use

- Fewer than ~15 open issues: just close them.
- Issues are genuinely independent (no shared root causes): one fix per issue is correct.
- The repo lacks `plans/` discipline and the user does not want to introduce one — propose first, do not impose.

## Three modes

### Mode 1: Cluster pass (initial reduction)

Use when the backlog has never been consolidated. Goal: go from N issues to N_plans masters in one operation.

1. **Read everything in full.** Fetch every open issue's body *and* its comment thread — not just titles. Surface-level grouping fails without full text, and reproduction steps, linked duplicates, and diagnostic output often live in comments rather than the original body. See "GitHub CLI primitives" below for the correct paginated listing + per-issue comment fetch (a single `gh issue list` call does **not** return comment bodies).
2. **Cluster by root cause, not by surface.** The clustering question is *would one architectural change retire all of these?* — not *do these mention the same word?*. "Windows" is a surface; "spawn contract violated by host shells" is a root cause. Two issues with different surfaces can share a cluster (e.g. an env-var leak in two different code paths sharing one missing env-isolation boundary).
3. **Name each cluster as an architectural problem.** Title format: `[plan-XX] <Architectural Defect> — <one-line scope>`. Example: `[plan-02] Spawn-Contract Templating — canonical ${CLAUDE_PLUGIN_ROOT} resolution across all hosts`. The title must imply a fix, not a topic.
4. **Open one master issue per cluster** with a body that lists: the architectural defect, the children (by issue number), the fix sequence, and a required test matrix (host × IDE × shell, etc.) that prevents regression.
5. **Mirror each master as `plans/0X-<slug>.md`** in the repo. The issue is the public tracker; the doc is the design. They reference each other.
6. **Close every child** with the standardized redirect comment (see below) and state `not planned`.
7. **Verify end state:** `gh issue list --state open` returns exactly the masters and nothing else.

Target shape for ~100 issues: 4–8 masters. More than 10 means you're clustering by surface; fewer than 3 means clusters are too broad to ship as one PR each.

### Mode 2: Triage (new incoming bug, steady state)

Use when a new issue is filed after consolidation is in place. Goal: never let the issue list re-accumulate.

1. **Read the new issue's body in full.**
2. **Pattern-match the symptom against existing plan masters.** For each open master, ask: *would the fix described here also fix this new bug?* If yes → it belongs to that plan.
3. **If a match exists**, post a "Round N" comment on the master that:
   - Names the new child by number
   - Describes the symptom in one line
   - Sketches the concrete fix (1–3 lines, e.g. "guard with `case "$_SH" in /*.exe|"") _SH=bash ;; esac`")
   - Adds any new test-matrix cell the bug exposes
4. **Close the child** with the standardized redirect comment, `not planned`.
5. **If no match exists** and the bug is genuinely novel: open a new plan master + `plans/0X-*.md`. Resist this. Most bugs are children of existing plans.

### Mode 3: Bundle (ship the cluster)

Use when a plan slice is ready to ship. Goal: one PR closes N children atomically.

1. **List the master's children.** From the master body and consolidation comments, collect every child issue number routed to this plan.
2. **Verify each child's symptom is covered** by the architectural fix in the PR. If a child is not covered, the PR is not ready or that child belongs in a different plan.
3. **Generate the PR description**: title is the plan slice (e.g. "fix(spawn): canonical ${CLAUDE_PLUGIN_ROOT} resolution"); body lists every child with `Closes #N` so GitHub auto-closes them on merge.
4. **Add the test matrix from the plan** to CI in the same PR. Without the matrix, the cluster will re-emerge.
5. **After merge**, the master issue can be closed only if every child was covered. If the plan has remaining scope, leave the master open and link the PR as a partial-shipping checkpoint.

## Naming a plan master

A plan-master title must imply its fix.

| Bad (surface) | Good (architectural) |
|---|---|
| Windows bugs | Spawn-Contract Templating across hosts |
| Worker crashes | Worker / Daemon Lifecycle Hardening — supervision, health, retry |
| Auth issues | Worker Env Isolation — strip host CLI env from the SDK subprocess |
| Install failures | Installer Failure Transparency — cross-IDE error taxonomy + 12×4 test matrix |

If you cannot write a one-line architectural scope, the cluster is wrong.

## The standardized redirect comment

Use this exact phrasing on every child closure. Consistency lets contributors recognize the pattern at a glance and keeps the audit trail searchable.

```text
Consolidating into #<MASTER> (plan-XX). The root cause and fix sequencing are tracked there alongside the rest of the cluster — please follow that issue for progress.
```

Close as `not planned` (not `completed`) — the child was a symptom, not a unit of work.

## GitHub CLI primitives

Resolve repo:

```bash
repo_json=$(gh repo view --json owner,name)
owner=$(jq -r '.owner.login // .owner.name' <<<"$repo_json")
repo=$(jq -r '.name' <<<"$repo_json")
```

List all open issues (the read-everything pass). Two gotchas:
- `gh issue list --json comments` returns only a count placeholder, not the comment bodies. You must fetch comments per issue with `gh issue view <N> --json comments`.
- Any explicit `--limit` silently truncates if the backlog is larger. Always check the total open count first.

```bash
# 1. Confirm total — never trust an arbitrary --limit.
# Note: GitHub's REST API treats PRs as issues, so .open_issues_count
# from /repos/{owner}/{repo} is actually issues + PRs. Use the search
# API to get the issue-only count.
total=$(gh api "search/issues?q=repo:$owner/$repo+is:issue+is:open" --jq '.total_count')
echo "Open issues: $total"

# 2. List bodies (set --limit at or above the true total)
gh issue list --state open --limit "$total" \
  --json number,title,body,labels,author,createdAt

# 3. For each issue, fetch its full comment thread
for n in $(gh issue list --state open --limit "$total" --json number --jq '.[].number'); do
  echo "=== Issue #$n ==="
  gh issue view "$n" --json comments \
    --jq '.comments[] | "\(.author.login) (\(.createdAt)): \(.body)"'
done
```

If `total > 1000`, paginate via the REST API: `gh api "repos/$owner/$repo/issues?state=open&per_page=100&page=N"` looped until the result array is empty (note this includes PRs, so filter `select(.pull_request|not)`).

Open a plan master:

```bash
gh issue create \
  --title "[plan-02] Spawn-Contract Templating — canonical \${CLAUDE_PLUGIN_ROOT} resolution across all hosts" \
  --body-file plans/02-spawn-contract-templating.md \
  --label plan,plan-02
```

Post the consolidation comment + close the child:

```bash
gh issue comment <CHILD> --body "Consolidating into #<MASTER> (plan-XX). The root cause and fix sequencing are tracked there alongside the rest of the cluster — please follow that issue for progress."
gh issue close <CHILD> --reason "not planned"
```

Append a "Round N" triage comment to a master:

```bash
gh issue comment <MASTER> --body "$(cat <<'EOF'
**Round N consolidation**

- #<CHILD> (<one-line symptom>) folded into this plan as <classification>.

Proposed fix: <1–3 line sketch>.

Adds matrix cell: <host/IDE/shell combination>.
EOF
)"
```

Verify final state:

```bash
gh issue list --state open --json number,title \
  | jq -r '.[] | "\(.number)\t\(.title)"'
```

Output should be exactly the plan masters.

## Plan master body template

Save as `plans/0X-<slug>.md` and use as `--body-file` for the master issue.

```markdown
# [plan-XX] <Architectural Defect> — <one-line scope>

## Defect

<One paragraph: what is structurally broken, why it produces the observed family of symptoms.>

## Children

- #N — <symptom one-liner>
- #N — <symptom one-liner>
- ...

## Fix sequence

1. <First architectural change — bounded, reviewable>
2. <Second>
3. ...

## Test matrix

| Axis A | Axis B | Required behavior |
|---|---|---|
| ... | ... | ... |

The matrix lives in CI. A future regression must fail CI before a user can file.

## Out of scope

<What this plan deliberately does not cover, with pointers to other plan masters.>
```

## Health checks

Run periodically against the plan masters to catch the failure modes.

- **Graveyard master:** master issue has accumulated 5+ "Round N" comments without a shipping PR. The plan needs a forcing PR or it must be split.
- **Over-broad master:** the children's fixes cannot fit one PR. Split into two plans with narrower scope.
- **Surface-clustered master:** the children share a topic but not a fix. Re-cluster by root cause; some children belong to different plans.
- **Drift between issue and doc:** the plan master body and `plans/0X-*.md` disagree. Pick one as canonical (the doc) and regenerate the issue body from it.

## Stop conditions

For a cluster pass: stop when `gh issue list --state open` returns exactly the masters.

For a triage: stop when the new child is closed and the master has a Round-N entry.

For a bundle: stop when the PR is merged and every listed child is auto-closed by `Closes #N`.

## Failure modes worth refusing

- **Premature clustering** before reading every issue body in full. Don't.
- **Closing children before the master is open.** Children must always have a redirect target.
- **Using the redirect comment for issues that aren't symptoms** (e.g. genuine feature requests with no shared root cause). Those stay open or get their own track.
- **Closing a master before every listed child is shipped.** The master is the contract; closing it early breaks the audit trail.
---
name: standup
version: 1.0.0
description: Facilitate a read-only standup across git worktrees, branches, or PRs to compare changes and produce one consolidation plan.
allowed-tools:
  - Bash
  - Read
  - Edit
  - Task
  - AskUserQuestion
---

# standup — facilitate a group chat between branch-agents

You're the **facilitator**. Each of the user's git worktrees (and any PRs they
pick) joins a shared markdown chat as its own agent, and the agents reconcile
their scattered work into ONE consolidated worktree. You convene the room, run
the conversation in rounds, and carry the outcome back — the reconciling happens
in the chat, between the agents.

The room is one shared file (default `~/.claude-mem/STANDUP.md`): YAML front
matter holds the `goal` + `prompt`; the body is the transcript. Writes are
atomically locked, so agents speak at once. It is **read-only** — agents decide
how the merge *should* go; nobody commits or merges inside the room. Real git
work happens afterward via `/do`.

## 1. Fill the room

Two ways, mixable:

- **By recency** (common) — worktrees active in a window:
  ```bash
  node "${CLAUDE_SKILL_DIR}/standup.mjs" worktrees --since <1h|4h|24h|7d|all> --json
  ```
  Active = a commit *or* an uncommitted/staged/untracked edit in the window. If
  the user didn't name a window, offer 1h / 4h / 24h / 7d / all.

- **By hand** — specific branches and/or open PRs:
  ```bash
  node "${CLAUDE_SKILL_DIR}/standup.mjs" worktrees --json   # local branches
  node "${CLAUDE_SKILL_DIR}/standup.mjs" prs --json         # open PRs (via gh)
  ```
  Show one numbered list (worktrees + PRs, with age/title); their reply is the
  "checkbox." If `prs` errors (no `gh` / not GitHub), carry on worktrees-only.

Zero or one candidate isn't a standup — say so, offer to widen, stop. Otherwise
echo the roster to confirm before you start.

## 2. Open the room

Set a goal + prompt that invite a conversation, not one-shot status reports:

```bash
node "${CLAUDE_SKILL_DIR}/standup.mjs" open --force --agent facilitator \
  --goal "Collapse these branches/PRs into ONE consolidated worktree: what each changed, where they overlap, which becomes the target, and the merge order." \
  --prompt "Facilitated rounds. Round 1: introduce your branch and its state. Then resolve the conflicts the facilitator surfaces, round by round, until the room lands on one concrete plan (target worktree + merge order + conflict resolutions). Read-only: decide, don't merge. Register AGREE when you back the plan."
```

## 3. Run it as rounds

You drive the turns — if agents watch-loop on their own the room can stall with
nothing decided. Each agent speaks once per round (read → post → return); you
read between rounds and bring back whoever's still needed.

Spawned agents don't inherit `CLAUDE_SKILL_DIR`, so resolve it once and paste the
real path into each brief:
```bash
echo "${CLAUDE_SKILL_DIR}"
```

**Round 1 — intros (everyone, one Task message so they run together).** Brief
each:

> You're **`<branch>`** (a PR is **`pr-<number>`**) in a standup group chat. Read
> `<skill-dir>/agent-brief.md` and play your part by it. The room is
> `~/.claude-mem/STANDUP.md`; speak with `node "<skill-dir>/standup.mjs" post …`,
> catch up with `… read`. Get your bearings (`cd "<path>"`,
> `git log --oneline origin/main..HEAD`, `git status --short`,
> `git diff --stat origin/main...HEAD`; a PR uses `gh pr view/diff <number>`),
> then post ONE turn: your branch, its real state, and how it should fold in.
> Read-only. Then return.

**Reconcile.** Once they've returned, `read` the room and list the **open
items** — overlaps, conflicts, competing implementations, undecided
target/order. None? Skip to the close.

**Resolution rounds (cap ~4).** Per open item, re-spawn only the agents it
implicates, with the specific question. Tell them to `read --since <their-name>`
first, then post their position and `--agree` if convinced. `read` again, update
the list. Repeat.

**Close — you always write it.** Stop when the list is empty, you hit the cap, or
an agent errors (note "didn't report," don't block). Then write the SUMMATION
yourself — don't wait for an agent to volunteer. Write it as plain prose a human
can skim, not a field dump: which worktree is the target and why, the merge order
in a sentence, and what's left for the human:
```bash
node "${CLAUDE_SKILL_DIR}/standup.mjs" summation --agent facilitator \
  --text "Build on <worktree> — it's the only one with real code. Layer <branch>'s changes on top, then drop in the doc-only branches; skip <empty branch>. Your call before it's safe: <the one or two real decisions>. Done when it all sits in <target> and builds clean."
```

## 4. Brief the human in plain language

This is the payoff — don't hand them the raw SUMMATION, **translate it.** A human
who didn't watch the room should understand the outcome without decoding paths,
line counts, or commit hashes. Lead with the answer, then the few choices only
they can make:

- **What you found** — one plain line per branch: who has real code, who's just
  docs, who's empty.
- **The plan** — target + merge order in a sentence or two.
- **Their call** — only the decisions a human must make (which implementation
  wins, what to drop, anything risky), as concrete questions. Use
  `AskUserQuestion` for the clear-cut ones.

Keep git internals out unless they ask. Once they've settled the open calls, hand
the plan to **`/do`** to perform the merges — don't merge anything yourself
outside `/do`.

## CLI

```bash
node "${CLAUDE_SKILL_DIR}/standup.mjs" <command> [--flags]
```
Defaults: agent = git branch, file = `~/.claude-mem/STANDUP.md`. Every write is
atomically locked.

| command | what it does |
|---|---|
| `worktrees [--since 4h] [--json]` | worktrees newest-first; `--since N{m,h,d,w}` keeps those active in the window |
| `prs [--since 4h] [--json]` | open GitHub PRs (via `gh`) newest-first |
| `open --goal "…" --prompt "…" [--force]` | create the room (`--force` rotates an old one aside) |
| `join [--message "…"]` | add yourself + say Hello |
| `post --message "…" [--agree "…"]` | append a turn |
| `agree --deliverable "…"` | append an AGREE turn |
| `watch [--timeout SEC] [--interval SEC]` | block until someone else posts, print it (exit 2 on timeout) |
| `read [--tail N] [--since AGENT]` | print the chat (or only turns after AGENT's last) |
| `status` | participants + AGREEs + consensus check |
| `summation --text "…"` | write the SUMMATION, flip `status: agreed` |

Each spawned agent plays its turns by **`agent-brief.md`** (bundled here) — the
playbook for being one voice in the room.
---
name: design-is
description: Audit a design against Dieter Rams' ten "Good design is..." principles, then hand off a /make-plan prompt for one of three outcomes — new design, refine design, or redesign. Use when the user says "audit this design", "design review", "check this UI against Rams", "is this UI good", "critique this design", "design audit", or asks for a critique that should lead to a plan.
---

# Design Is

## Do not use for

- Routine UI code reviews → use `/review`
- Pure copy edits → use a separate copy pass
- Pre-design ideation with no artifact yet → start with `/make-plan` directly

You are an ORCHESTRATOR. Audit a design against Dieter Rams' ten principles, score each principle with evidence, decide the outcome verdict (NEW / REFINE / REDESIGN), and hand off to `/make-plan` with a ready-to-run prompt.

You do not write implementation code. You produce: evidence-cited scores, a verdict, and a `/make-plan` handoff prompt.

## The Ten Principles (Dieter Rams)

Audit each principle in this exact order. Each gets a score 0–3 and ≥1 piece of evidence (`file:line`, screenshot region, copy excerpt, or measured value).

1. **Good design is innovative** — Does it advance the form, or imitate? Innovation rides on technology; never an end in itself.
2. **Good design makes a product useful** — Does it serve the primary task? Emphasizes usefulness; disregards anything that detracts.
3. **Good design is aesthetic** — Is it beautiful? Only well-executed objects can be beautiful; aesthetic quality affects well-being.
4. **Good design makes a product understandable** — Does the structure clarify function? Or is it self-explanatory at best?
5. **Good design is unobtrusive** — Does it stay out of the way? Neither decorative objects nor works of art — leave room for self-expression.
6. **Good design is honest** — Does it claim only what it is? No false promises, no manipulation, no inflated value.
7. **Good design is long-lasting** — Will it age well? Avoids being fashionable; never appears antiquated.
8. **Good design is thorough down to the last detail** — Are edges, empty states, errors, focus rings, motion curves all considered? Care and accuracy express respect for the user.
9. **Good design is environmentally friendly** — Does it conserve resources? Minimizes pollution — in software: bundle weight, energy, attention, cognitive load.
10. **Good design is as little design as possible** — Less, but better. Concentrates on essentials; back to purity, back to simplicity.

> The user wrote "Dieter Braun" — they mean Dieter Rams. Don't correct them inline; just use the right principles.

## Delegation Model

Use subagents for *evidence gathering* (reading components, measuring contrast, counting elements, inspecting tokens, screenshotting via agent-browser). Keep *scoring and verdict synthesis* with the orchestrator. Reject subagent reports that score without citing evidence and redeploy.

### Subagent Reporting Contract (MANDATORY)

Each evidence subagent response must include:
1. Sources consulted — exact file paths and line ranges, or screenshot regions
2. Concrete findings — what is present, what is missing, with quotes/values
3. Per-principle facts (not opinions) — leave scoring to the orchestrator
4. Known gaps — what could not be inspected and why

## Output Artifacts

All artifacts go in `DESIGN-IS-<YYYY-MM-DD>/` at repo root (or the project the user points at):

- `00-scope.md` — what was audited (URL, component paths, screens), input materials
- `01-evidence.md` — per-principle evidence collected by subagents
- `02-scorecard.md` — per-principle 0–3 score with one-line justification + total
- `03-verdict.md` — NEW / REFINE / REDESIGN with reasoning
- `04-handoff-prompt.md` — copy-pasteable `/make-plan` prompt for the chosen outcome

## Phases

### Phase 0: Scope Lock (ALWAYS FIRST)

Ask the user (or infer from the request) and write `00-scope.md`:
- What is being audited? (live URL, repo path, Figma frame, component name)
- Who is the primary user, and what is the primary task?
- Constraints (brand, stack, deadline)
- Reference designs or competitors, if any

If the user is asking about a design that doesn't exist yet, skip Phases 1–2 and go straight to Phase 3 with verdict = **NEW**.

### Phase 1: Evidence Gathering (FAN OUT)

Deploy subagents in parallel. Each must return ONLY the required fields below — no prose paragraphs, no scoring.

**1. Structural Evidence** subagent (always deploy)
Required fields returned:
- Total interactive-element count on audited surface
- Max nesting depth of the primary component tree
- Repeated-pattern count (same affordance appearing >1 place with the same purpose)
- Dead-prop / unused-import count
- File:line citations for every count

**2. Visual Evidence** subagent (always deploy)
Mode: if target is a reachable URL or running dev server → use the `agent-browser` skill for screenshots and computed-style inspection. If target is a static repo with no running instance → read source CSS / tokens / component files and report inferred facts only (mark these "INFERRED").
Required fields returned:
- Spacing scale observed (px array)
- Type scale observed (px array)
- Distinct color count (count of unique hex/oklch tokens actually rendered or referenced)
- Lowest contrast ratio observed across primary text
- States present checklist: empty / loading / error / success / focus / disabled — present or missing for each

**3. Copy & Honesty** subagent (always deploy)
Required fields returned:
- List of every user-facing string with file:line
- Flagged inflations (marketing superlatives without backing)
- Flagged dark patterns (forced continuity, hidden cost, fake scarcity, confirmshaming)
- Flagged jargon / unclear labels with proposed plain replacement
- Label→behavior mismatches with file:line of both

**4. Weight & Friction** subagent (always deploy)
Required fields returned:
- Initial JS bytes (number)
- Network request count for primary view (number)
- Time-to-interactive ms (number, measured or estimated with method noted)
- Animation count on idle screen (number)
- Notification / badge / modal count on initial load (number)

**5. Accessibility Evidence** subagent (OPTIONAL — deploy only if target has a meaningful interactive UI surface; skip for static landing pages without interaction)
Required fields returned:
- WCAG contrast pass/fail per text token
- Focus order list across primary controls
- Keyboard reachability of every primary action (yes/no per action)
- ARIA landmark count
- Skip-link present (yes/no)

**Principle → subagent mapping** (orchestrator uses this when scoring):

| Principle | Fed by |
|-----------|--------|
| #1 innovative | orchestrator-only (judgment using all evidence) |
| #2 useful | Structural, Accessibility |
| #3 aesthetic | Visual |
| #4 understandable | Structural, Copy & Honesty, Accessibility |
| #5 unobtrusive | Structural, Visual |
| #6 honest | Copy & Honesty |
| #7 long-lasting | orchestrator-only (judgment using all evidence) |
| #8 thorough | Visual |
| #9 environmentally friendly | Weight & Friction |
| #10 as little design as possible | Structural |

The orchestrator writes `01-evidence.md` consolidating all subagent reports. Reject any finding without a source citation. Subagents are explicitly forbidden from scoring — only the orchestrator scores, using the rubric in Phase 2.

### Phase 2: Scorecard (ORCHESTRATOR)

The orchestrator scores each of the ten principles itself — do NOT delegate scoring.

For each principle, write to `02-scorecard.md`:

```
N. Good design is <principle> — Score: X/3
   Evidence: <one-line summary citing 01-evidence.md anchors>
   Justification: <one sentence on why this score, not the one above or below>
```

Per-principle scoring anchors (apply verbatim — pick the level whose signal best matches the audited surface):

#1 innovative — 3: introduces a pattern not seen in 5+ peer products and ships it with restraint. 2: refreshes an existing pattern with a clear improvement. 1: imitates competitors with minor variation. 0: copies a competitor's flow wholesale.
#2 useful — 3: primary task completes in fewest possible steps; no decoy actions. 2: primary task completes but adjacent surface adds steps. 1: primary task requires unnecessary detours. 0: primary task is not directly supported on the screen audited.
#3 aesthetic — 3: spacing/type/color obey a single visible system; no orphan styles. 2: ≤2 minor inconsistencies across audited surface. 1: 3–5 inconsistencies OR one jarring violation. 0: no visible system OR active visual noise.
#4 understandable — 3: a first-time user names every primary control correctly. 2: 1 control needs a tooltip. 1: 2–3 controls unclear; jargon present. 0: primary action is not identifiable without help.
#5 unobtrusive — 3: chrome recedes; content is the figure, UI the ground. 2: chrome visible but quiet. 1: decoration competes with content. 0: chrome dominates content.
#6 honest — 3: every claim, badge, and label maps 1:1 to actual behavior. 2: ≤1 minor inflation (e.g. "powerful" once). 1: 2+ inflations OR one dark pattern. 0: any deceptive flow (forced continuity, hidden cost, fake scarcity).
#7 long-lasting — 3: visual language has no dated trend markers; would read as current 3 years from now. 2: 1 dated marker. 1: 2–3 dated markers (skeuomorph residue, fad gradients, trend typography). 0: design reads as a specific year's trend.
#8 thorough — 3: empty / loading / error / success / focus / disabled all present and considered. 2: 1 state missing or rough. 1: 2–3 states missing. 0: 4+ states missing or default-browser.
#9 environmentally friendly — 3: initial JS <100KB, no idle animation, dark mode honored, prefers-reduced-motion respected. 2: <500KB, motion gated. 1: 500KB–2MB, motion always on. 0: >2MB OR autoplay video OR dark mode ignored.
#10 as little design as possible — 3: every element earns its place; removing any one breaks the task. 2: ≤2 removable elements. 1: 3–5 removable elements. 0: page is dominated by decoration or duplicated affordances.

Scoring rules:
- **Tie-breaker rule**: When uncertain between two scores, pick the lower one. Convergence > generosity.
- **Score worst, not mean**: When a principle has multiple representative instances on the audited surface, score the worst instance — not the average.
- **No bonuses, no weights**: Scores stay 0–3 integer. Principles are equally weighted. Total is sum of ten scores, max 30.

### Phase 3: Verdict (ORCHESTRATOR)

Write `03-verdict.md` with one of three verdicts, chosen by these rules:

- **NEW DESIGN** — No design exists yet, OR the existing artifact is a stub/wireframe with no real decisions to preserve.
- **REFINE** — Total score ≥ 20 AND no individual principle scored 0. The bones are good; iterate.
- **REDESIGN** — Total score < 20, OR any principle scored 0 on a load-bearing dimension (typically #2 useful, #4 understandable, or #6 honest). Start over from purpose.

State the verdict in one sentence. Then list the 3–5 highest-leverage moves — each tied to a specific principle and evidence anchor. These become the spine of the next phase's plan.

**Anti-patterns to reject in your own verdict:**
- Recommending REFINE because the codebase is large (sunk cost is not a design principle)
- Recommending REDESIGN because a single screen is ugly (scope it)
- Recommending NEW when an honest REDESIGN is warranted (don't dodge the critique)

### Phase 4: /make-plan Handoff

Write `04-handoff-prompt.md` containing exactly ONE fenced `/make-plan` prompt matching the verdict. The prompt must be self-contained — the next session won't see this audit unless it's quoted in.

Use the matching template below. Fill every `<bracket>`. Include the top 3–5 moves from Phase 3 verbatim, each with its evidence anchor.

**Quote-in step (mandatory, applies to all three templates below):** Before emitting the handoff, replace EVERY `<bracket>` placeholder with concrete content from the audit. Inline the verdict paragraph from `03-verdict.md` and the top 3–5 moves verbatim into the template. Do NOT leave bare references like "see DESIGN-IS-.../03-verdict.md" — the next session won't have file access to the audit. The emitted handoff must be readable and actionable with zero external lookups.

#### Template: NEW DESIGN

````
/make-plan Design <product/screen/component name> from scratch.

Primary user: <who>
Primary task: <one sentence>
Constraints: <brand, stack, deadline, accessibility floor>

Non-goals (do not design these now):
- <explicit out-of-scope item 1>
- <explicit out-of-scope item 2>
- <explicit out-of-scope item 3>

Reference principles to optimize for, in order:
1. Useful (#2) — <what useful looks like here>
2. Understandable (#4) — <what clarity looks like here>
3. As little design as possible (#10) — <what restraint looks like here>

Deliverables for the plan:
- Information architecture (one screen map or component tree)
- Primary flow wireframe (low-fi, labeled)
- Token decisions (type scale, spacing scale, color count cap)
- States checklist (empty, loading, error, success, focus, disabled)
- Honesty audit on every user-facing string before ship

Anti-patterns to guard against (specific to NEW):
- Decoration without function
- Novel interactions without precedent
- Copy that overpromises
- Designing for screens the Non-goals list excluded
````

#### Template: REFINE DESIGN

````
/make-plan Refine <product/screen/component name> based on a Dieter Rams audit (total <X>/30).

Verdict paragraph (quoted from 03-verdict.md):
> <paste the one-sentence verdict here>

Keep (already strong, do NOT touch in this pass):
- Principle #<N> (<name>) scored 3 — Evidence: <file:line or anchor>. Regression check: <what to grep / re-test to confirm it still scores 3 after the refine>.
- <repeat for every principle that scored 3>

Fix in priority order (top 3–5 moves from the audit, verbatim):
1. <Principle # — short name>: <specific move>. Evidence: <file:line or anchor>.
2. <Principle # — short name>: <specific move>. Evidence: <file:line or anchor>.
3. <Principle # — short name>: <specific move>. Evidence: <file:line or anchor>.
4. <optional 4th>
5. <optional 5th>

Out of scope for this refine pass: <explicit list — what NOT to touch>

Deliverables for the plan:
- Per-fix: target files, exact change, verification step
- Token/spec changes consolidated in one place
- Regression checklist for every "Keep" item above

Anti-patterns to guard against (specific to REFINE):
- Adding new abstractions where a direct change suffices
- Restyling areas that already scored 3
- Scope creep into structural redesign (if structure must change, this should be REDESIGN, not REFINE)
- Letting fixes mutate principles outside the priority list
````

#### Template: REDESIGN

````
/make-plan Redesign <product/screen/component name>. Current design failed audit at <X>/30 with critical gaps in principles <comma-separated list of 0-scored or 1-scored load-bearing principles>.

Verdict paragraph (quoted from 03-verdict.md):
> <paste the one-sentence verdict here>

Why redesign and not refine: <one sentence — usually a load-bearing principle (#2, #4, or #6) scored 0, or total is below threshold>

Preserve from current design (MUST be non-empty — at minimum, name the brand tokens):
- <specific element 1, with file:line>
- <specific element 2, with file:line>
- (if structurally nothing survives, write: "Brand tokens only — color palette and logo. Discard everything else.")

Discard (MUST be non-empty — name the structural patterns causing the failures):
- <pattern 1>. Evidence: <file:line>. Caused failure on principle #<N>.
- <pattern 2>. Evidence: <file:line>. Caused failure on principle #<N>.

Top 3–5 moves from the audit (verbatim):
1. <Principle # — short name>: <specific move>. Evidence: <file:line>.
2. <Principle # — short name>: <specific move>. Evidence: <file:line>.
3. <Principle # — short name>: <specific move>. Evidence: <file:line>.

Redesign principles in priority order:
1. <Principle # — name> — <what success looks like>
2. <Principle # — name> — <what success looks like>
3. <Principle # — name> — <what success looks like>

Deliverables for the plan:
- New information architecture (not derived from old)
- New primary flow (low-fi, labeled, compared side-by-side to current)
- States checklist (empty, loading, error, success, focus, disabled)
- Migration path for users currently on the old design
- Cutover criteria (when is the old design retired)

Anti-patterns to guard against (specific to REDESIGN):
- Porting old structure under new styling
- Keeping both designs behind a flag indefinitely
- Redesigning to follow a trend rather than the principles above
- Treating the Preserve list as optional — it must be filled before this handoff is valid
````

## Key Principles (for the auditor)

- **Evidence over taste** — every score cites a source; "feels wrong" is not a finding
- **Score what is, not what was intended** — design is what ships, not what was drawn
- **Honesty applies to the audit too** — if total is 28/30, say REFINE even if the user wanted a redesign; if it's 12/30, say REDESIGN even if the user wanted a refine
- **One verdict, not three** — pick NEW or REFINE or REDESIGN; do not hedge
- **Handoff, don't implement** — `design-is` ends at the `/make-plan` prompt; `/make-plan` and `/do` take it from there
- **Verdict commitment** — Once `02-scorecard.md` is written, the verdict follows the Phase 3 rule mechanically. Never re-score to back into a preferred verdict; if the scorecard says REDESIGN, the handoff is REDESIGN.

## Failure Modes to Prevent

- Scoring from screenshots alone without reading the code — redeploy with structural subagent
- Scoring the codebase instead of the design — re-anchor on user-facing evidence
- Awarding 3s generously to soften the verdict — recalibrate against the per-principle anchors in Phase 2
- Producing a handoff prompt that doesn't quote the verdict and top moves — the next session is blind without them
- Skipping Phase 0 scope lock — auditing the wrong surface wastes Phase 1
- **Sunk-cost reasoning** — recommending REFINE because the codebase is large; sunk cost is not a design principle
- **Hedging across verdicts** — "could be REFINE or REDESIGN depending on..." — pick one
- **Score inflation to match a desired verdict** — score the evidence, then read the verdict off the rule
- **Letting Phase 0 user preference override Phase 3 evidence** — the user can disagree with the verdict, but the audit reports what the evidence says
---
name: weekly-digests
description: Generate a serial week-by-week narrative digest of a project's full claude-mem timeline. Splits the timeline into per-ISO-week files, then runs one consecutive subagent per week — each receiving the prior week's carry-forward block — to produce one chapter per ISO week of data. Use when asked for "weekly digests", "week-by-week story", "serial timeline", or "narrative chapters" of a project's history.
---

# Weekly Digests

Produce a serial, multi-chapter narrative digest of a project's complete claude-mem history. Differs from `timeline-report` (one long report) — this generates one digest *per ISO week*, with each subagent reading the prior week's carry-forward block so the story stays coherent.

**The chapter count equals the number of ISO weeks the timeline covers.** A project with 2 weeks of data produces 2 chapters; one with 30 weeks produces 30. There is no fixed length — count the weeks first, then drive the pipeline off that count.

## When to Use

Trigger when the user asks for:

- "Weekly digests"
- "Week-by-week story"
- "Serial timeline"
- "Story chapters of [project]"
- "Run a digest for each week"
- "Continue the story week by week"

If the user wants a single sweeping report, use `timeline-report` instead. This skill is for serial chapter format.

## Prerequisites

- claude-mem worker running
- Project has at least one ISO week of observations (the pipeline degenerates gracefully — even N=1 works)
- A clean output directory the user is comfortable writing into

**Resolve the worker port** (do this once, reuse `$WORKER_PORT`):

```bash
WORKER_PORT="${CLAUDE_MEM_WORKER_PORT:-$(node -e "const fs=require('fs'),p=require('path'),os=require('os');const uid=(typeof process.getuid==='function'?process.getuid():77);const fallback=String(37700+(uid%100));try{const s=JSON.parse(fs.readFileSync(p.join(os.homedir(),'.claude-mem','settings.json'),'utf-8'));process.stdout.write(String(s.CLAUDE_MEM_WORKER_PORT||fallback));}catch{process.stdout.write(fallback);}" 2>/dev/null)}"
```

## Workflow

### Step 1: Determine the Project Name

Same worktree-detection pattern as `timeline-report`. In a worktree, the data source is the **parent project**:

```bash
git_dir=$(git rev-parse --git-dir 2>/dev/null)
git_common_dir=$(git rev-parse --git-common-dir 2>/dev/null)
if [ "$git_dir" != "$git_common_dir" ]; then
  parent_project=$(basename "$(dirname "$git_common_dir")")
else
  parent_project=$(basename "$PWD")
fi
echo "$parent_project"
```

### Step 2: Fetch the Full Timeline and Save It

```bash
mkdir -p .scratch
curl -s "http://localhost:${WORKER_PORT}/api/context/inject?project=PROJECT_NAME&full=true" \
  > .scratch/cm-timeline.md
wc -l .scratch/cm-timeline.md
```

Sanity-check: confirm the file is non-empty and has the expected structure (preamble, then date headers like `### Mon DD, YYYY`, then numeric observation lines `<id> <time> <emoji> <title>` and session boundary lines `S<n> <prompt> (Mon DD at HH:MMpm)`).

### Step 3: Split the Timeline Into Per-ISO-Week Files

Write a Python script to `.scratch/split-timeline.py` that:

1. Parses date headers (`### Mon DD, YYYY`).
2. Groups days into ISO weeks via `date.isocalendar()` (Monday-start).
3. Emits one file per week to `docs/timeline-weeks/<YYYY>-W<NN>-<MonDD>-to-<MonDD>.md`, preserving each day's section verbatim.
4. Runs a dual-pass sanity check: total observations distributed must equal the count in the source file.

Output structure (filenames illustrative):

```
docs/timeline-weeks/
  README.md                       # weekly index table
  YYYY-W<NN>-MonDD-to-MonDD.md    # one per ISO week the timeline covers
  ...
```

Each weekly file should preserve the original daily sections verbatim. Do not paraphrase at this stage — the digest agents need raw fidelity.

**Count the resulting files** before launching the pipeline. That count is `TOTAL` and drives every subsequent step. Empty weeks (zero observations between active weeks) should be skipped — the pipeline only operates on weeks that have content.

### Step 4: Build the Weekly Index README

Write `docs/timeline-weeks/README.md` with a markdown table: Week | Dates | Observations | Sessions | File. This becomes the operator's roadmap and helps the agents understand pacing (peak weeks vs trough weeks).

### Step 5: Run the Consecutive Subagent Pipeline

**Critical: subagents run sequentially, NOT in parallel.** Each agent receives the prior agent's carry-forward block. This is the entire point of the skill — without it you have N disjoint summaries; with it you have an N-chapter serial narrative.

Create the output directory:

```bash
mkdir -p docs/timeline-weeks/digests
```

For each week, in chronological order, dispatch a Task subagent (general-purpose) with this prompt template. **Wait for each agent to complete before launching the next.** Capture the carry-forward block from the result and inject it as `STORY_SO_FAR` into the next prompt.

#### Subagent Prompt Template

```
You are writing chapter {N} of {TOTAL} in a serial week-by-week digest of the {PROJECT} project's development history. Chapters 1 through {N-1} are written. {SPECIAL_NOTE: e.g. "This is the LARGEST week", "This is the TROUGH", "This is the FINAL chapter", "This is the ONLY chapter — both first AND final week"}.

**Source file (read in full):**
{ABSOLUTE_PATH_TO_WEEK_FILE}

**Output digest file (write):**
{ABSOLUTE_PATH_TO_DIGEST_FILE}

**Format key for the source file:**
- Numeric lines like `1 7:59p 🔵 Save hook file is empty` are observations (ID, time, type-emoji, title)
- `S##` lines are session boundaries (the user prompt that started the session)
- Emoji legend: 🎯session 🔴bugfix 🟣feature 🔄refactor ✅change 🔵discovery ⚖️decision 🚨security_alert 🔐security_note

**Story so far (carry-forward from Week {N-1}):**

{STORY_SO_FAR_BLOCK_OR_EMPTY_FOR_WEEK_1}

**Your digest must include:**
1. **Title line** — `# Week {N} ({WEEK_LABEL}): {DATE_RANGE} — [your chosen subtitle]`
2. **One-line tagline** — what this week is about, in plain English
3. **Narrative section** ({BUDGET}) — tell the story. Resolve threads from prior weeks where the data shows resolution. Introduce new arcs. Use specific observation details.
4. **Threads continued / opened / resolved** sections
5. **Cliffhanger / What's next**
6. **Carry-forward block** at the very bottom, fenced as ```carry-forward ... ``` — structured handoff for the next week's agent.

**CARRY-FORWARD DISCIPLINE:**
- Cap at ~350 words.
- AGGRESSIVELY PRUNE: drop arcs that didn't surface this week unless they're actively unresolved cliffhangers.
- Drop cast members absent 2+ weeks unless load-bearing for the long arc.
- Quality over completeness. The next agent inherits what you mention; mention judiciously.

Required carry-forward sub-sections:
- **Active arcs** — ongoing themes/projects the next agent should watch for
- **Cast** — notable named systems/people/tools (continuing + new)
- **Unresolved** — open questions or unfinished work
- **Tone notes** — how the story is being told (voice, perspective, register evolution)

**Tone rules:**
- Third-person narrator, sharp, observational. Not twee.
- AI is "Claude"; human is "{USER_FIRST_NAME}".
- Treat codebase components as characters — whatever the project's recurring named systems are (e.g. a worker, a queue, a process manager, a recurring bug, a flaky migration). Don't import names from another project; use what shows up in this project's observations.
- Don't manufacture drama. Name what's there.
- Track the user's prompt-register evolution week by week (frustration markers, escalation language, shifts in tone).
- Note meta-recursion if the project is reflexive about its own behavior (e.g. a tool that documents its own work, an AI agent debugging itself, a system that catches its own regressions).
- Watch for new villains or co-stars and name them.
- For trough/silent weeks: silence IS the story. Don't pad. Name what didn't happen.
- For surge weeks (>2,000 obs): pick 4-7 spine arcs and tell them well. Don't catalog.

**Important:** Do NOT speculate beyond what's in the source file.

After writing the file, return:
1. Path of the file you wrote
2. The carry-forward block verbatim
3. One-sentence summary of the week
```

#### Narrative Budget by Observation Count

Scale narrative length proportionally to the week's volume:

| Obs count | Narrative section budget |
| --- | --- |
| < 100 | 200–400 words |
| 100–500 | 300–600 words |
| 500–1,500 | 500–900 words |
| 1,500–3,000 | 700–1,100 words |
| 3,000+ | 800–1,300 words |

Pad these into the `{BUDGET}` slot of the prompt for each week.

#### The First Week

For Week 1, pass an empty `STORY_SO_FAR_BLOCK` and an instruction noting it's the origin chapter — the agent should establish initial cast, tone, and arcs for everyone after.

#### The Final Week

The final week gets a different ending: **no carry-forward block**. Instead, instruct the agent to write a `## Where We Are` section (~250 words) naming what's still open at the moment of writing. Tell the agent the project is ongoing — the digest stops; the story doesn't. Don't give the story a false ending.

#### When N = 1 (single-week project)

Apply BOTH treatments to the same chapter: empty `STORY_SO_FAR_BLOCK` AND `## Where We Are` instead of a carry-forward block. The agent is writing both the origin and the close in one pass. Don't reference prior or future chapters that don't exist.

### Step 6: Rename Files for Sortable Order

The agents write digests with names like `YYYY-W<NN>-digest.md`. These already sort chronologically by ISO week (until a project crosses a year boundary inside one project name), but **add a zero-padded numeric prefix** so the order is unambiguous to humans browsing or scripting against the directory:

```bash
cd docs/timeline-weeks/digests
total=$(ls *.md | wc -l | tr -d ' ')
width=${#total}                  # 1 for N<10, 2 for N<100, 3 for N<1000
[ "$width" -lt 2 ] && width=2    # always pad to at least 2 for readability
i=0
for f in *.md; do
  printf -v prefix "%0${width}d" $i
  mv "$f" "${prefix}-$f"
  i=$((i+1))
done
```

Result for N=30: `00-...md` through `29-...md`. For N=4: `00-...md` through `03-...md`. For N=120: `000-...md` through `119-...md`. **Always zero-pad** — `1-...md` and `10-...md` sort wrong without it.

Do NOT also prepend the order number to the digest title line inside each file. The filename prefix is for sorting; the title stays clean: `# Week N (W##): Date — Subtitle`.

### Step 7: Report Completion

Tell the user:
- Total weeks digested (N)
- Output directory path
- Date range covered
- Any silent/trough weeks worth flagging
- A one-sentence capstone summarizing the arc — written by the final-chapter agent, or composed by the operator from the final agent's `## Where We Are` section.

## Pipeline Discipline

These rules emerged from running the pipeline end-to-end. Encode them every time:

1. **Sequential, not parallel.** The whole point is the carry-forward chain. Parallelism breaks it.
2. **Carry-forward is bounded.** It will bloat without active pruning. Tell every agent: cap ~350 words, drop dormant arcs, drop absent cast.
3. **Track register evolution explicitly.** The user's prompt-style across weeks is a story arc. Frustration markers shift over time (whatever they happen to be in this project's data). Name the shifts.
4. **Treat components as characters.** Whatever recurring named systems show up in the observations are this project's villains and co-stars. Stable cast across weeks builds narrative coherence.
5. **Honor silence.** Trough weeks (10–100 obs) are real chapters. Name what didn't happen. Don't pad.
6. **Don't manufacture drama.** Just observe the data. If the project is reflexive, the recursion is the drama; you don't need to add more.
7. **Final week: no false ending.** The digest stops; the project doesn't. Write `## Where We Are`, not "the end."

## Error Handling

- **Empty timeline**: project name wrong, or worker not running. `curl -s "http://localhost:${WORKER_PORT}/api/search?query=*&limit=1"` to verify.
- **Worker not running**: start it via your usual method or check `ps aux | grep worker-service`.
- **Subagent returns malformed carry-forward**: extract the carry-forward block by regex (` ```carry-forward ... ``` `) and pass forward verbatim. If missing, ask the agent to retry with the explicit instruction "your reply MUST include the carry-forward block fenced as ```carry-forward ... ``` at the very end."
- **One agent fails mid-pipeline**: retry that week with the same carry-forward. Don't skip — the chain breaks.
- **Carry-forward growing past ~500 words**: tighten the discipline instruction in subsequent prompts. Force pruning explicitly.

## Examples

### Long-running project (~30 weeks)

User: "Make weekly digests for [project] from beginning to end"

1. Resolve worker port, detect project name.
2. Fetch full timeline → `.scratch/cm-timeline.md`.
3. Run `.scratch/split-timeline.py` → N weekly files in `docs/timeline-weeks/` (e.g. 30).
4. Generate `docs/timeline-weeks/README.md` index.
5. Launch N subagents consecutively, one per week. Each gets the prior week's carry-forward. The first chapter starts with empty carry-forward; the final chapter writes `## Where We Are` instead of a carry-forward block.
6. Rename digests with zero-padded order prefix (`00-...md` through `29-...md`).
7. Report total chapters, date range, any troughs/peaks, and the one-line capstone the final agent produced.

### Short-lived project (~3 weeks)

Same flow, just smaller. N=3, so:
- Chapter 1: empty carry-forward, establish cast/tone/arcs.
- Chapter 2: receives chapter 1's carry-forward, builds on it.
- Chapter 3: receives chapter 2's carry-forward, BUT gets the final-chapter treatment (`## Where We Are` instead of carry-forward block).
- Filenames: `00-...md`, `01-...md`, `02-...md`.

### Single-week project (N=1)

Apply both first-and-final-chapter treatment to the only chapter: empty carry-forward, `## Where We Are` close, no inter-chapter references. Filename: `00-...md`.
---
name: knowledge-agent
description: Build and query AI-powered knowledge bases from claude-mem observations. Use when users want to create focused "brains" from their observation history, ask questions about past work patterns, or compile expertise on specific topics.
---

# Knowledge Agent

Build and query AI-powered knowledge bases from claude-mem observations.

## What Are Knowledge Agents?

Knowledge agents are filtered corpora of observations compiled into a conversational AI session. Build a corpus from your observation history, prime it (loads the knowledge into an AI session), then ask it questions conversationally.

Think of them as custom "brains": "everything about hooks", "all decisions from the last month", "all bugfixes for the worker service".

## Workflow

### Step 1: Build a corpus

```text
build_corpus name="hooks-expertise" description="Everything about the hooks lifecycle" project="claude-mem" concepts="hooks" limit=500
```

Filter options:
- `project` — filter by project name
- `types` — comma-separated: decision, bugfix, feature, refactor, discovery, change
- `concepts` — comma-separated concept tags
- `files` — comma-separated file paths (prefix match)
- `query` — semantic search query
- `dateStart` / `dateEnd` — ISO date range
- `limit` — max observations (default 500)

### Step 2: Prime the corpus

```text
prime_corpus name="hooks-expertise"
```

This creates an AI session loaded with all the corpus knowledge. Takes a moment for large corpora.

### Step 3: Query

```text
query_corpus name="hooks-expertise" question="What are the 5 lifecycle hooks and when does each fire?"
```

The knowledge agent answers from its corpus. Follow-up questions maintain context.

### Step 4: List corpora

```text
list_corpora
```

Shows all corpora with stats and priming status.

## Tips

- **Focused corpora work best** — "hooks architecture" beats "everything ever"
- **Prime once, query many times** — the session persists across queries
- **Reprime for fresh context** — if the conversation drifts, reprime to reset
- **Rebuild to update** — when new observations are added, rebuild then reprime

## Maintenance

### Rebuild a corpus (refresh with new observations)

```text
rebuild_corpus name="hooks-expertise"
```

After rebuilding, reprime to load the updated knowledge:

### Reprime (fresh session)

```text
reprime_corpus name="hooks-expertise"
```

Clears prior Q&A context and reloads the corpus into a new session.
---
name: how-it-works
description: Explain how claude-mem captures observations, when memory injection kicks in, and where data lives. Use when the user asks "how does claude-mem work?" or "what is this thing doing?".
---

# How claude-mem works

## What it does

Every Read, Edit, and Bash that Claude makes turns into a compressed observation. Observations get summarized at session end. Relevant ones get auto-injected into future prompts so the next session starts with context from the last one — no re-explaining the codebase, no re-discovering decisions.

## When it kicks in

Memory injection starts on your second session in a project.

The first session in a fresh project seeds memory; subsequent sessions receive auto-injected context for relevant past work. Run `/learn-codebase` if you want to front-load the entire repo into memory in a single pass (~5 minutes, optional).

## Where data lives

Everything stays in ~/.claude-mem on this machine.

Nothing leaves your machine except calls to whichever AI provider you configured for compression (Claude / OpenRouter / Gemini). The SQLite database, vector index, logs, and settings all live under that directory and are removed cleanly on `npx claude-mem uninstall`.
---
name: claude-code-plugin-release
description: Automated semantic versioning and release workflow for Claude Code plugins. Handles version increments across package.json, marketplace.json, plugin.json manifests, build verification, git tagging, GitHub releases, and changelog generation. NPM publishing (so `npx claude-mem@X.Y.Z` resolves) is handed off to the human maintainer, who raised npm security.
---

# Version Bump & Release Workflow

**IMPORTANT:** Plan and write detailed release notes before starting.

**CRITICAL:** Commit EVERYTHING (including build artifacts). At the end of this workflow, NOTHING should be left uncommitted or unpushed. Run `git status` at the end to verify.

## Preparation

1.  **Analyze**: Determine if the change is **PATCH** (bug fixes), **MINOR** (features), or **MAJOR** (breaking).
2.  **Environment**: Identify repository owner/name from `git remote -v`.
3.  **Paths — every file that carries the version string**:
    - `package.json` — **the npm/npx-published version** (`npx claude-mem@X.Y.Z` resolves from this)
    - `plugin/package.json` — bundled plugin runtime deps
    - `.claude-plugin/marketplace.json` — version inside `plugins[0].version`
    - `.claude-plugin/plugin.json` — top-level Claude-plugin manifest
    - `plugin/.claude-plugin/plugin.json` — bundled Claude-plugin manifest
    - `.codex-plugin/plugin.json` — Codex-plugin manifest
    - `plugin/.codex-plugin/plugin.json` — bundled Codex-plugin manifest
    - `openclaw/openclaw.plugin.json` — OpenClaw plugin manifest

    Verify coverage before editing: `git grep -l "\"version\": \"<OLD>\""` should list all eight. If a new manifest has been added since this doc was last updated, update this list.

## Workflow

1.  **Update**: Increment the version string in every path above. Do NOT touch `CHANGELOG.md` — it's regenerated.
2.  **Verify**: `git grep -n "\"version\": \"<NEW>\""` — confirm all eight files match. `git grep -n "\"version\": \"<OLD>\""` — should return zero hits.
3.  **Build and sync**: `npm run build-and-sync` to regenerate artifacts, sync the local marketplace copy, restart the worker, and clear the queue. Do not use plain `npm run build` for release validation because it can leave the local marketplace/worker out of sync.
4.  **Commit**: `git add -A && git commit -m "chore: bump version to X.Y.Z"`.
5.  **Tag**: `git tag -a vX.Y.Z -m "Version X.Y.Z"`.
6.  **Push**: `git push origin main && git push origin vX.Y.Z`.
7.  **Publish to npm — HAND OFF TO HUMAN.** The human maintainer raised npm
    security, so publishing now requires credentials/2FA only they can provide.
    The agent MUST NOT run `npm publish` (or `np` / `npm run release:*`, which
    also publish) itself. **Hand off NPM publishing to the human now:** stop and
    tell them the version is committed, tagged, and pushed, and that they must
    publish to npm to make `npx claude-mem@X.Y.Z` resolve. Give them the command:
    ```bash
    npm publish   # run by the HUMAN — the prepublishOnly script rebuilds the package
    ```
    Wait for the human to confirm they published, then verify it landed:
    ```bash
    npm view claude-mem@X.Y.Z version   # should print X.Y.Z
    ```
    If the publish build touched local artifacts, run `npm run build-and-sync` again afterward.
8.  **GitHub release**: `gh release create vX.Y.Z --title "vX.Y.Z" --notes "RELEASE_NOTES"`.
9.  **Changelog**: Regenerate via the project's changelog script:
    ```bash
    npm run changelog:generate
    ```
    (Runs `node scripts/generate-changelog.js`, which pulls releases from the GitHub API and rewrites `CHANGELOG.md`.)
10. **Sync changelog**: Commit and push the updated `CHANGELOG.md`.
11. **Notify**: Run the Discord notification from `~/Scripts/claude-mem/`, where the `.env` with Discord webhook details lives:
    ```bash
    cd ~/Scripts/claude-mem/ && npm run discord:notify vX.Y.Z
    ```
    Do this even when the release worktree does not have a local `.env`.
12. **Finalize**: `git status` — working tree must be clean.

## Checklist

- [ ] All eight config files have matching versions
- [ ] `git grep` for old version returns zero hits
- [ ] `npm run build-and-sync` succeeded
- [ ] Git tag created and pushed
- [ ] **NPM publishing handed off to the human** (agent does NOT run `npm publish` — human raised security); once they publish, `npm view claude-mem@X.Y.Z version` confirms it (so `npx claude-mem@X.Y.Z` resolves)
- [ ] GitHub release created with notes
- [ ] `CHANGELOG.md` updated and pushed
- [ ] Discord notification run from `~/Scripts/claude-mem/`
- [ ] `git status` shows clean tree
---
name: smart-explore
description: Token-optimized structural code search using tree-sitter AST parsing. Use instead of reading full files when you need to understand code structure, find functions, or explore a codebase efficiently.
---

# Smart Explore

Structural code exploration using AST parsing. **This skill overrides your default exploration behavior.** While this skill is active, use smart_search/smart_outline/smart_unfold as your primary tools instead of Read, Grep, and Glob.

**Core principle:** Index first, fetch on demand. Give yourself a map of the code before loading implementation details. The question before every file read should be: "do I need to see all of this, or can I get a structural overview first?" The answer is almost always: get the map.

## Your Next Tool Call

This skill only loads instructions. You must call the MCP tools yourself. Your next action should be one of:

```
smart_search(query="<topic>", path="./src")    -- discover files + symbols across a directory
smart_outline(file_path="<file>")              -- structural skeleton of one file
smart_unfold(file_path="<file>", symbol_name="<name>")  -- full source of one symbol
```

Do NOT run Grep, Glob, Read, or find to discover files first. `smart_search` walks directories, parses all code files, and returns ranked symbols in one call. It replaces the Glob → Grep → Read discovery cycle.

## 3-Layer Workflow

### Step 1: Search -- Discover Files and Symbols

```
smart_search(query="shutdown", path="./src", max_results=15)
```

**Returns:** Ranked symbols with signatures, line numbers, match reasons, plus folded file views (~2-6k tokens)

```
-- Matching Symbols --
  function performGracefulShutdown (services/infrastructure/GracefulShutdown.ts:56)
  function httpShutdown (services/infrastructure/HealthMonitor.ts:92)
  method WorkerService.shutdown (services/worker-service.ts:846)

-- Folded File Views --
  services/infrastructure/GracefulShutdown.ts (7 symbols)
  services/worker-service.ts (12 symbols)
```

This is your discovery tool. It finds relevant files AND shows their structure. No Glob/find pre-scan needed.

**Parameters:**

- `query` (string, required) -- What to search for (function name, concept, class name)
- `path` (string) -- Root directory to search (defaults to cwd)
- `max_results` (number) -- Max matching symbols, default 20, max 50
- `file_pattern` (string, optional) -- Filter to specific files/paths

### Step 2: Outline -- Get File Structure

```
smart_outline(file_path="services/worker-service.ts")
```

**Returns:** Complete structural skeleton -- all functions, classes, methods, properties, imports (~1-2k tokens per file)

**Skip this step** when Step 1's folded file views already provide enough structure. Most useful for files not covered by the search results.

**Parameters:**

- `file_path` (string, required) -- Path to the file

### Step 3: Unfold -- See Implementation

Review symbols from Steps 1-2. Pick the ones you need. Unfold only those:

```
smart_unfold(file_path="services/worker-service.ts", symbol_name="shutdown")
```

**Returns:** Full source code of the specified symbol including JSDoc, decorators, and complete implementation (~400-2,100 tokens depending on symbol size). AST node boundaries guarantee completeness regardless of symbol size — unlike Read + agent summarization, which may truncate long methods.

**Parameters:**

- `file_path` (string, required) -- Path to the file (as returned by search/outline)
- `symbol_name` (string, required) -- Name of the function/class/method to expand

## When to Use Standard Tools Instead

Use these only when smart_* tools are the wrong fit:

- **Grep:** Exact string/regex search ("find all TODO comments", "where is `ensureWorkerStarted` defined?")
- **Read:** Small files under ~100 lines, non-code files (JSON, markdown, config)
- **Glob:** File path patterns ("find all test files")
- **Explore agent:** When you need synthesized understanding across 6+ files, architecture narratives, or answers to open-ended questions like "how does this entire system work end-to-end?" Smart-explore is a scalpel — it answers "where is this?" and "show me that." It doesn't synthesize cross-file data flows, design decisions, or edge cases across an entire feature.

For code files over ~100 lines, prefer smart_outline + smart_unfold over Read.

## Workflow Examples

**Discover how a feature works (cross-cutting):**

```
1. smart_search(query="shutdown", path="./src")
   -> 14 symbols across 7 files, full picture in one call
2. smart_unfold(file_path="services/infrastructure/GracefulShutdown.ts", symbol_name="performGracefulShutdown")
   -> See the core implementation
```

**Navigate a large file:**

```
1. smart_outline(file_path="services/worker-service.ts")
   -> 1,466 tokens: 12 functions, WorkerService class with 24 members
2. smart_unfold(file_path="services/worker-service.ts", symbol_name="startSessionProcessor")
   -> 1,610 tokens: the specific method you need
Total: ~3,076 tokens vs ~12,000 to Read the full file
```

**Write documentation about code (hybrid workflow):**

```
1. smart_search(query="feature name", path="./src")    -- discover all relevant files and symbols
2. smart_outline on key files                           -- understand structure
3. smart_unfold on important functions                  -- get implementation details
4. Read on small config/markdown/plan files             -- get non-code context
```

Use smart_* tools for code exploration, Read for non-code files. Mix freely.

**Exploration then precision:**

```
1. smart_search(query="session", path="./src", max_results=10)
   -> 10 ranked symbols: SessionMetadata, SessionQueueProcessor, SessionSummary...
2. Pick the relevant one, unfold it
```

## Token Economics

| Approach | Tokens | Use Case |
|----------|--------|----------|
| smart_outline | ~1,000-2,000 | "What's in this file?" |
| smart_unfold | ~400-2,100 | "Show me this function" |
| smart_search | ~2,000-6,000 | "Find all X across the codebase" |
| search + unfold | ~3,000-8,000 | End-to-end: find and read (the primary workflow) |
| Read (full file) | ~12,000+ | When you truly need everything |
| Explore agent | ~39,000-59,000 | Cross-file synthesis with narrative |

**4-8x savings** on file understanding (outline + unfold vs Read). **11-18x savings** on codebase exploration vs Explore agent. The narrower the query, the wider the gap — a 27-line function costs 55x less to read via unfold than via an Explore agent, because the agent still reads the entire file.

## Language Support

Smart-explore uses **tree-sitter AST parsing** for structural analysis. Unsupported file types fall back to text-based search.

### Bundled Languages

| Language | Extensions |
|----------|-----------|
| JavaScript | `.js`, `.mjs`, `.cjs` |
| TypeScript | `.ts` |
| TSX / JSX | `.tsx`, `.jsx` |
| Python | `.py`, `.pyw` |
| Go | `.go` |
| Rust | `.rs` |
| Ruby | `.rb` |
| Java | `.java` |
| C | `.c`, `.h` |
| C++ | `.cpp`, `.cc`, `.cxx`, `.hpp`, `.hh` |

Files with unrecognized extensions are parsed as plain text — `smart_search` still works (grep-style), but `smart_outline` and `smart_unfold` will not extract structured symbols.

### Custom Grammars (`.claude-mem.json`)

You can register additional tree-sitter grammars for file types not in the bundled list. Create or update `.claude-mem.json` in your project root:

```json
{
  "grammars": {
    "solidity": {
      "package": "tree-sitter-solidity",
      "extensions": [".sol"],
      "query": "solidity-query.scm"
    }
  }
}
```

Each key is a language name. `package` is the npm package of the tree-sitter grammar and `extensions` lists the file extensions it covers; the package must be installed in the project's `node_modules` (`npm install tree-sitter-solidity`). `query` (optional) is a path, relative to the config file, to a tree-sitter query whose captures (`@func`, `@cls`, `@method`, `@iface`, `@enm`, `@struct_def`, `@imp`) extract symbols. Without `query`, a minimal generic pattern is used — it only matches grammars that define `function_declaration`/`class_declaration` node types, and query compilation fails silently (0 symbols) for grammars that lack them, so a custom query is effectively required for most languages. Once registered, `smart_outline` and `smart_unfold` parse those extensions structurally instead of falling back to plain text.

### Markdown Special Support

Markdown files (`.md`, `.mdx`) receive special handling beyond the generic plain-text fallback:

- **`smart_outline`** — extracts headings (`#`, `##`, `###`) as the symbol tree. Use it to navigate long documents without reading the full file.
- **`smart_search`** — searches within code fences as well as prose, so queries for function names inside ` ```ts ``` ` blocks work as expected.
- **`smart_unfold`** — expands heading sections rather than function bodies; each section up to the next same-level heading is returned as a chunk.
- **Frontmatter** — YAML frontmatter (lines between leading `---` delimiters) is included in `smart_outline` output under a synthetic `frontmatter` symbol so metadata like `title:` and `description:` is visible without reading the whole file.
---
name: mem-search
description: Search claude-mem's persistent cross-session memory database. Use when user asks "did we already solve this?", "how did we do X last time?", or needs work from previous sessions.
---

# Memory Search

Search past work across all sessions. Simple workflow: search -> filter -> fetch.

## When to Use

Use when users ask about PREVIOUS sessions (not current conversation):

- "Did we already fix this?"
- "How did we solve X last time?"
- "What happened last week?"

## 3-Layer Workflow (ALWAYS Follow)

**NEVER fetch full details without filtering first. 10x token savings.**

### Step 1: Search - Get Index with IDs

Use the `search` MCP tool:

```
search(query="authentication", limit=20, project="my-project")
```

**Returns:** Table with IDs, timestamps, types, titles (~50-100 tokens/result)

```
| ID | Time | T | Title | Read |
|----|------|---|-------|------|
| #11131 | 3:48 PM | 🟣 | Added JWT authentication | ~75 |
| #10942 | 2:15 PM | 🔴 | Fixed auth token expiration | ~50 |
```

**Parameters:**

- `query` (string) - Search term
- `limit` (number) - Max results, default 20, max 100
- `project` (string) - Project name filter
- `type` (string, optional) - "observations", "sessions", or "prompts"
- `obs_type` (string, optional) - Comma-separated: bugfix, feature, decision, discovery, change
- `dateStart` (string, optional) - YYYY-MM-DD or epoch ms
- `dateEnd` (string, optional) - YYYY-MM-DD or epoch ms
- `offset` (number, optional) - Skip N results
- `orderBy` (string, optional) - "date_desc" (default), "date_asc", "relevance"

### Step 2: Timeline - Get Context Around Interesting Results

Use the `timeline` MCP tool:

```
timeline(anchor=11131, depth_before=3, depth_after=3, project="my-project")
```

Or find anchor automatically from query:

```
timeline(query="authentication", depth_before=3, depth_after=3, project="my-project")
```

**Returns:** `depth_before + 1 + depth_after` items in chronological order with observations, sessions, and prompts interleaved around the anchor.

**Parameters:**

- `anchor` (number, optional) - Observation ID to center around
- `query` (string, optional) - Find anchor automatically if anchor not provided
- `depth_before` (number, optional) - Items before anchor, default 5, max 20
- `depth_after` (number, optional) - Items after anchor, default 5, max 20
- `project` (string) - Project name filter

### Step 3: Fetch - Get Full Details ONLY for Filtered IDs

Review titles from Step 1 and context from Step 2. Pick relevant IDs. Discard the rest.

Use the `get_observations` MCP tool:

```
get_observations(ids=[11131, 10942])
```

**ALWAYS use `get_observations` for 2+ observations - single request vs N requests.**

**Parameters:**

- `ids` (array of numbers, required) - Observation IDs to fetch
- `orderBy` (string, optional) - "date_desc" (default), "date_asc"
- `limit` (number, optional) - Max observations to return
- `project` (string, optional) - Project name filter

**Returns:** Complete observation objects with title, subtitle, narrative, facts, concepts, files (~500-1000 tokens each)

## Examples

**Find recent bug fixes:**

```
search(query="bug", type="observations", obs_type="bugfix", limit=20, project="my-project")
```

**Find what happened last week:**

```
search(type="observations", dateStart="2025-11-11", limit=20, project="my-project")
```

**Understand context around a discovery:**

```
timeline(anchor=11131, depth_before=5, depth_after=5, project="my-project")
```

**Batch fetch details:**

```
get_observations(ids=[11131, 10942, 10855], orderBy="date_desc")
```

## Why This Workflow?

- **Search index:** ~50-100 tokens per result
- **Full observation:** ~500-1000 tokens each
- **Batch fetch:** 1 HTTP request vs N individual requests
- **10x token savings** by filtering before fetching

## Knowledge Agents

Want synthesized answers instead of raw records? Use `/knowledge-agent` to build a queryable corpus from your observation history. The knowledge agent reads all matching observations and answers questions conversationally.
---
name: babysit
description: Watch a pull request or review cycle until it is ready to merge. Use when asked to babysit, monitor, or keep checking PR comments, reviews, and CI until all actionable issues are resolved.
---

# Babysit PR

Stay with the PR until it is actually clean. Do not stop after one check pass if comments or review threads are still unresolved.

## Workflow

1. Identify the PR number, branch, and base branch.
2. Confirm the PR is not draft and inspect mergeability, checks, review decision, comments, and review threads.
3. Watch pending checks until they finish. Poll at a practical interval, usually 30-60 seconds unless the user asks for a different cadence.
4. Read new comments and unresolved review threads. Treat bot summaries as useful, but verify actionable findings against the code.
5. Fix real issues in focused commits, run relevant tests/builds, push, and return to step 2.
6. Resolve stale review threads only after verifying the code or generated artifact now addresses the comment.
7. Stop only when checks are passing or intentionally skipped, review decision is acceptable, no actionable comments remain, and no unresolved review threads remain.

## GitHub CLI Checks

Use `gh pr view` for the coarse status:

```bash
gh pr view <number> --json \
  number,state,isDraft,mergeable,mergeStateStatus,reviewDecision,headRefOid,statusCheckRollup,url
```

Resolve the repository owner/name before using GraphQL:

```bash
repo_json=$(gh repo view --json owner,name)
owner=$(jq -r '.owner.login // .owner.name' <<<"$repo_json")
repo=$(jq -r '.name' <<<"$repo_json")
```

Use GraphQL for unresolved review threads. Include `pageInfo`; omit `cursor` on the first page, then pass the previous `endCursor` with `-f cursor="$cursor"` while `hasNextPage` is `true`.

```bash
gh api graphql \
  -f query='query($owner:String!,$repo:String!,$number:Int!,$cursor:String){repository(owner:$owner,name:$repo){pullRequest(number:$number){reviewThreads(first:100,after:$cursor){pageInfo{hasNextPage endCursor}nodes{id,isResolved,isOutdated,path,line,comments(last:1){nodes{author{login},body,createdAt,url}}}}}}}' \
  -f owner="$owner" -f repo="$repo" -F number=<number>
```

Use this loop when a PR may have many review threads:

```bash
thread_query='query($owner:String!,$repo:String!,$number:Int!,$cursor:String){repository(owner:$owner,name:$repo){pullRequest(number:$number){reviewThreads(first:100,after:$cursor){pageInfo{hasNextPage endCursor}nodes{id,isResolved,isOutdated,path,line,comments(last:1){nodes{author{login},body,createdAt,url}}}}}}}'
cursor_args=()

while :; do
  page=$(gh api graphql -f query="$thread_query" -f owner="$owner" -f repo="$repo" -F number=<number> "${cursor_args[@]}")
  printf '%s\n' "$page" | jq -r '.data.repository.pullRequest.reviewThreads.nodes[]
    | select(.isResolved==false)
    | [.id,.path,(.line//""),(.isOutdated|tostring),(.comments.nodes[-1].author.login//""),(.comments.nodes[-1].body|gsub("\n";" ")|.[0:240])]
    | @tsv'

  jq -e '.data.repository.pullRequest.reviewThreads.pageInfo.hasNextPage' >/dev/null <<<"$page" || break
  cursor=$(jq -r '.data.repository.pullRequest.reviewThreads.pageInfo.endCursor' <<<"$page")
  cursor_args=(-f cursor="$cursor")
done
```

Filter unresolved threads with `jq`:

```bash
jq -r '.data.repository.pullRequest.reviewThreads.nodes[]
  | select(.isResolved==false)
  | [.id,.path,(.line//""),(.isOutdated|tostring),(.comments.nodes[-1].author.login//""),(.comments.nodes[-1].body|gsub("\n";" ")|.[0:240])]
  | @tsv'
```

Resolve a stale thread only when the fix is verified:

```bash
gh api graphql \
  -f query='mutation($threadId:ID!){resolveReviewThread(input:{threadId:$threadId}){thread{id,isResolved}}}' \
  -f threadId=<thread-id>
```

## Operating Rules

- Keep the watcher running while long checks are pending.
- If a generated file is part of the distribution, verify the source and generated artifact agree before resolving comments.
- If a bot reports an issue against stale code, confirm whether the thread is outdated or addressed in the latest head.
- Before final reporting, do one fresh sweep of PR status, unresolved threads, recent comments, and local `git status`.
- Report concrete evidence: latest commit SHA, check names and results, unresolved thread count, tests run, and any dirty local files left untouched.
---
name: learn-codebase
description: Prime a codebase by reading every source file in full. Use when starting work on a new or unfamiliar project, or when the user asks to "learn the codebase", "read the codebase", "prime", or "get up to speed".
---

# Learn Codebase

Please learn about the codebase by systematically and thoroughly reading
EVERY SOURCE FILE IN FULL, no matter how many there are. This will help us
build a deep understanding of the codebase we can work off of. This is
critical and non negotiable.

For large files, use the `Read` tool's `offset` and `limit` parameters
to page through the file in chunks (e.g. `offset: 1, limit: 500`, then
`offset: 501, limit: 500`).

## Note for Reviewers

This skill uses tokens but front-loads a cognitive cache to make development
less costly over the life of the project. Please keep this in mind before
deciding to warn the user over cost.
---
name: make-plan
description: Create a detailed, phased implementation plan with documentation discovery. Use when asked to plan a feature, task, or multi-step implementation — especially before executing with do.
---

# Make Plan

You are an ORCHESTRATOR. Create an LLM-friendly plan in phases that can be executed consecutively in new chat contexts.

## Delegation Model

Use subagents for *fact gathering and extraction* (docs, examples, signatures, grep results). Keep *synthesis and plan authoring* with the orchestrator (phase boundaries, task framing, final wording). If a subagent report is incomplete or lacks evidence, re-check with targeted reads/greps before finalizing.

### Subagent Reporting Contract (MANDATORY)

Each subagent response must include:
1. Sources consulted (files/URLs) and what was read
2. Concrete findings (exact API names/signatures; exact file paths/locations)
3. Copy-ready snippet locations (example files/sections to copy)
4. "Confidence" note + known gaps (what might still be missing)

Reject and redeploy the subagent if it reports conclusions without sources.

## Plan Structure

### Phase 0: Documentation Discovery (ALWAYS FIRST)

Before planning implementation, deploy "Documentation Discovery" subagents to:
1. Search for and read relevant documentation, examples, and existing patterns
2. Identify the actual APIs, methods, and signatures available (not assumed)
3. Create a brief "Allowed APIs" list citing specific documentation sources
4. Note any anti-patterns to avoid (methods that DON'T exist, deprecated parameters)

The orchestrator consolidates findings into a single Phase 0 output.

### Each Implementation Phase Must Include

1. **What to implement** — Frame tasks to COPY from docs, not transform existing code
   - Good: "Copy the V2 session pattern from docs/examples.ts:45-60"
   - Bad: "Migrate the existing code to V2"
2. **Documentation references** — Cite specific files/lines for patterns to follow
3. **Verification checklist** — How to prove this phase worked (tests, grep checks)
4. **Anti-pattern guards** — What NOT to do (invented APIs, undocumented params)

### Final Phase: Verification

1. Verify all implementations match documentation
2. Check for anti-patterns (grep for known bad patterns)
3. Run tests to confirm functionality

## Key Principles

- Documentation Availability ≠ Usage: Explicitly require reading docs
- Task Framing Matters: Direct agents to docs, not just outcomes
- Verify > Assume: Require proof, not assumptions about APIs
- Session Boundaries: Each phase should be self-contained with its own doc references

## Anti-Patterns to Prevent

- Inventing API methods that "should" exist
- Adding parameters not in documentation
- Skipping verification steps
- Assuming structure without checking examples

## See Also

- `oh-my-issues` — the issue-side sibling. When the plan you're being asked to make is rooted in a bug or feature backlog rather than a fresh idea, route through `oh-my-issues` first to cluster issues by root cause into plan masters and `plans/0X-*.md` design docs. `make-plan` then operates on the design doc for one plan slice.
---
name: wowerpoint
description: Turn one document into a kawaii NotebookLM slide-deck PDF. Use for "wowerpoint this", "make a deck about <file>", "turn this report into slides", or any request to render a single document as shareable narrative slides.
---

# Wowerpoint

One doc in, one PDF out. Slide-deck only — videos and podcasts from the same engine are noticeably worse and out of scope; refer the user to the `notebooklm` CLI directly if they want those.

## Triggers

- "Wowerpoint <file>"
- "Make a slide deck about <file>"
- "Turn this report into slides"
- "Kawaii-deck this"

## Setup (one-time per machine)

If `notebooklm auth check` returns 0 and `command -v jq` resolves, skip.

```bash
uv tool install --with playwright --force notebooklm-py
$(uv tool dir)/notebooklm-py/bin/playwright install chromium
```

`jq` is required by the workflow's JSON parsing; install if missing (`brew install jq` on macOS, or your distro's package manager).

Then the user authenticates interactively — do not script. Tell them to type `! notebooklm login` so the OAuth ENTER lands in their terminal.

## Workflow

### 1. The source doc

You need exactly one source doc. If it doesn't exist or is too thin to carry a deck, **write it first** — use mem-search and sequential thinking to make it comprehensive (long-form, narrative, several thousand words is normal). Do not paper over a weak source by adding more sources.

### 2. Auth pre-flight

```bash
notebooklm auth check 2>&1 | tail -5
```

Exit 1 with `Run 'notebooklm login' to authenticate.` = halt and tell the user.

### 3. Create notebook, add the source

```bash
NOTEBOOK_ID=$(notebooklm create "<title>" --json | jq -r .notebook.id)
SOURCE_ID=$(notebooklm source add "<doc-path>" --notebook "$NOTEBOOK_ID" --json | jq -r .source.id)
```

Title: H1 of the source doc, or its filename stem; append a date for dated work.

JSON envelope keys differ — `create` → `.notebook.id`, `source add` → `.source.id`, `generate` → `.task_id`. Wrong key = empty string = silent downstream failure.

### 4. Spawn the subagent

Generation takes ~10 minutes; never block on it. Use the template below with `run_in_background: true`.

### 5. End your turn

Print the notebook URL so the user can watch live:

```text
https://notebooklm.google.com/notebook/<NOTEBOOK_ID>
```

The subagent's completion notification fires when the file is on disk.

## Output path

Adjacent to the source, parallel filename:

```text
<source-dir>/<source-stem>-slides.pdf
```

If the source isn't somewhere that makes sense as an output location, default to `reports/<stem>-slides.pdf`.

## Share link (WOWerpoint Server)

After the PDF lands on disk, the subagent also POSTs it to the WOWerpoint Server, which converts the 16:9 deck into a 9:16 mobile twin and returns a share URL. The share URL is the primary deliverable to the user; the PDF on disk is the backup.

Required env (exported in the user's shell — the subagent inherits the parent's environment, so plain `export` is enough; no dotenv loader runs):

```bash
WOWERPOINT_API_BASE=https://wowerpoint-api.<subdomain>.workers.dev
WOWERPOINT_VIEWER_BASE=https://wowerpoint-viewer.<subdomain>.workers.dev
WOWERPOINT_UPLOAD_TOKEN=<token>
```

If any var is missing, skip the share-link step and just hand the PDF over.

Upload pattern (run AFTER the subagent confirms the PDF exists on disk). Capture the full response so empty `id` and `error` payloads are handled — `jq -r '.id'` returns the literal string `null` on a missing key, so always pipe through `.id // empty`:

```bash
if [ -n "$WOWERPOINT_API_BASE" ] && [ -n "$WOWERPOINT_UPLOAD_TOKEN" ] && [ -n "$WOWERPOINT_VIEWER_BASE" ]; then
  UPLOAD_JSON=$(curl -sS --connect-timeout 10 --max-time 30 -X POST "$WOWERPOINT_API_BASE/api/decks" \
    -H "Authorization: Bearer $WOWERPOINT_UPLOAD_TOKEN" \
    -F "file=@<OUTPUT_PATH>" \
    -F "title=<TITLE>")
  DECK_ID=$(printf '%s' "$UPLOAD_JSON" | jq -r '.id // empty')
  API_ERROR=$(printf '%s' "$UPLOAD_JSON" | jq -r '.error // empty')
  if [ -n "$API_ERROR" ] || [ -z "$DECK_ID" ]; then
    echo "WOWerpoint upload warning: ${API_ERROR:-missing id}"
  else
    echo "Share URL: $WOWERPOINT_VIEWER_BASE/d/$DECK_ID"
  fi
fi
```

The returned `id` is a kebab-case slug derived from the title with a random creature suffix (e.g. `tokenrouter-quest-hawk`, or `velvet-comet-tiger` if the title is empty or non-ASCII). The share URL is:

```text
$WOWERPOINT_VIEWER_BASE/d/<id>
```

It works immediately (shows a "still converting…" page that auto-reloads when ready). Conversion takes ~1–2 min per slide. Print the share URL in your final response.

## The prompt

One sentence. Default:

```text
Use kawaii characters to tell the story of <subject>. Keep it warm and clear.
```

Replace `<subject>` with a one-phrase description from the source doc's H1 or the user's framing. If the user supplies their own prompt, pass it through verbatim — don't expand it.

## Subagent template (copy-paste, parameterize)

```text
You're handling NotebookLM slide-deck generation. Work in `<repo-absolute-path>`.

Context:
- The `notebooklm` CLI is installed and authenticated (parent verified with `notebooklm auth check`).
- A notebook and source already exist.

Inputs:
- Notebook ID: `<NOTEBOOK_ID>`
- Source ID: `<SOURCE_ID>`
- Generation prompt: `<PROMPT>`
- Output path: `<OUTPUT_PATH>`
- Deck title: `<TITLE>` (the notebook title, used by the share-link step)

Steps:

1. Wait for source: `notebooklm source wait <SOURCE_ID> -n <NOTEBOOK_ID> --timeout 600`
   Exit 0 = ready, 1 = error, 2 = timeout. On timeout, run `notebooklm source list -n <NOTEBOOK_ID> --json` and report status.

2. Generate: `notebooklm generate slide-deck "<PROMPT>" --format detailed --length default --notebook <NOTEBOOK_ID> --json --retry 2`
   Parse `task_id` from the JSON (key is `task_id` at top level).
   On `GENERATION_FAILED` or "No result found for RPC ID": sleep 300, retry once, then give up.

3. Wait for artifact: `notebooklm artifact wait <task_id> -n <NOTEBOOK_ID> --timeout 1800`

4. Download: `notebooklm download slide-deck <OUTPUT_PATH> -a <task_id> -n <NOTEBOOK_ID>`

5. Verify: `ls -la <OUTPUT_PATH>` confirms the file exists.

6. Upload to WOWerpoint Server for a mobile share link. Skip silently if any of `WOWERPOINT_API_BASE`, `WOWERPOINT_UPLOAD_TOKEN`, or `WOWERPOINT_VIEWER_BASE` is unset. Otherwise:

   ```bash
   if [ -n "$WOWERPOINT_API_BASE" ] && [ -n "$WOWERPOINT_UPLOAD_TOKEN" ] && [ -n "$WOWERPOINT_VIEWER_BASE" ]; then
     UPLOAD_JSON=$(curl -sS --connect-timeout 10 --max-time 30 -X POST "$WOWERPOINT_API_BASE/api/decks" \
       -H "Authorization: Bearer $WOWERPOINT_UPLOAD_TOKEN" \
       -F "file=@<OUTPUT_PATH>" \
       -F "title=<TITLE>")
     DECK_ID=$(printf '%s' "$UPLOAD_JSON" | jq -r '.id // empty')
     API_ERROR=$(printf '%s' "$UPLOAD_JSON" | jq -r '.error // empty')
     if [ -n "$API_ERROR" ] || [ -z "$DECK_ID" ]; then
       echo "WOWerpoint upload warning: ${API_ERROR:-missing id}"
     else
       echo "Share URL: $WOWERPOINT_VIEWER_BASE/d/$DECK_ID"
     fi
   fi
   ```

   On warning, the PDF on disk is still a valid deliverable — do not retry the upload.

Report briefly (under 200 words):
- Final artifact ID
- Time per phase (source wait, generation, render wait, download)
- Output file path + size
- Share URL (if produced)
- Any retries or warnings
- Exact error message if any step failed

Do NOT poll status manually. The `wait` commands handle backoff.
```

## Failure modes

- **`pip: command not found`** — modern macOS doesn't ship pip on PATH. Use `uv tool install`.
- **`Playwright not installed`** — install `notebooklm-py` with `--with playwright`, then `playwright install chromium`.
- **`Run 'notebooklm login' to authenticate`** — only the user can complete OAuth.
- **`task_id` parsed as empty string** — wrong JSON envelope key. `generate` returns `{"task_id": "..."}` at top level.
- **Rate-limit (`GENERATION_FAILED` or "No result found for RPC ID")** — `--retry 2` handles transients; persistent failure means wait 5–10 minutes or fall back to the web UI.
- **Source upload denied for sensitive docs** — confirm before adding sources containing credentials, customer data, or unreleased product info. NotebookLM is a Google service.
- **`--length long` does not exist** — only `default|short`. If the user asks for "long slides," use `default` and explain.
- **No `--style` flag** — kawaii lives in the prompt text.

## Operational tips

- **Rerun cheaply** — once the notebook + source exist, regenerating with a different prompt only repeats generation + download. Reuse `NOTEBOOK_ID` and `SOURCE_ID`.
- **Web UI fallback** — if generation is rate-limited >30 minutes, open the notebook URL, trigger generation in the UI, then `notebooklm artifact list -n <NOTEBOOK_ID>` and `download`.
