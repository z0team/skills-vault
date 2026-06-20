import json

with open("registry.json", "r") as f:
    data = json.load(f)

pack_count = data.get("pack_count", 0)

table = "| Pack Name | Description | Source |\n|---|---|---|\n"
for pack in data.get("packs", []):
    name = pack.get("id")
    desc = pack.get("description", "").replace("\n", " ").replace("|", " ")
    if len(desc) > 80: desc = desc[:77] + "..."
    src = pack.get("source")
    table += f"| `{name}` | {desc} | [Original Repo]({src}) |\n"

readme = f"""# Skills Vault

The largest unified open-source skill library for AI agents.

[![License: MIT](https://img.shields.io/badge/License-MIT-blue.svg)](https://opensource.org/licenses/MIT)
[![Skills: {pack_count}](https://img.shields.io/badge/skills-{pack_count}-brightgreen.svg)]()
[![Compatible with: Claude Code, Cursor, Copilot](https://img.shields.io/badge/compatible_with-Claude_Code_Cursor_Copilot-blueviolet.svg)]()

**{pack_count} production-grade AI skills · Unified format · Instant npx installation**

[Get Started](#quick-start) · [Available Packs](#available-packs) · [Contributing](#adding-a-new-pack)

---

## Give any AI agent the skills of a senior developer

Your AI agent knows how to code, but it doesn't know the specific nuances of your stack, your company's best practices, or how to use specialized tools—unless you give it those skills.

This repo contains **{pack_count} structured AI skill packs** from top open-source repositories. Every skill is normalized into a unified format, making it instantly compatible with Claude Code, Cursor, GitHub Copilot, Windsurf, OpenCode, Codex, and Agy.

## Quick start

The fastest way to give your agent superpowers is via `npx` (No cloning required):

```bash
# Option 1: npx (recommended)
npx skills add z0team/skills-vault
```

```bash
# Option 2: bash curl (Linux/Mac)
curl -fsSL https://raw.githubusercontent.com/z0team/skills-vault/main/get.sh | bash
```

```powershell
# Option 3: PowerShell (Windows)
iwr -useb https://raw.githubusercontent.com/z0team/skills-vault/main/get.ps1 | iex
```

An interactive menu will guide you through selecting the agent, the scope (local or global), and the specific skill packs you wish to install.

## Available Packs

{table}

## Architecture & Supported Agents

We maintain a normalized version of all skills. Under the hood, this repository runs a generation pipeline that converts `SKILL.md` files into the optimal format for each specific AI agent.

| Agent | Global Path | Local Path |
|---|---|---|
| `claude-code` | `~/.claude/skills/` | `<project>/.claude/skills/` |
| `cursor` | — (Not natively supported) | `<project>/.cursor/rules/` |
| `copilot` | `~/.claude/skills/` (fallback) | `<project>/.github/instructions/` |
| `windsurf` | `~/.claude/skills/` (fallback) | `<project>/.windsurf/rules/` |
| `agents-md` | `~/.claude/AGENTS.md` | `<project>/AGENTS.md` |
| `generic` | Raw `SKILL.md` | Raw `SKILL.md` |

## Adding a New Pack

Want to add your favorite repository to the Vault? It's simple!

```bash
# 1. Add your repository to SOURCES in scripts/ingest_external.py
# 2. Run the ingestion pipeline
python3 scripts/ingest_external.py

# 3. Build the registry
python3 scripts/build_registry.py

# 4. Export all dist formats
./scripts/build-dist.sh
```

*(Maintainers note: Ensure you commit `dist/`, `registry.json`, `get.sh`, and `cli.js` so they are immediately available for the npx installer).*

## License

Each pack retains its original license from its source repository. Please check the `pack.meta.json` inside each pack's directory for specific license notes before using third-party skills in commercial projects.
"""

with open("README.md", "w") as f:
    f.write(readme)
print("README.md generated successfully!")
