---
name: mksglu__ctx-insight
description: "|"
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
