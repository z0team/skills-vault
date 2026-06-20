# Skills Vault

The largest unified open-source skill library for AI agents.

[![License: MIT](https://img.shields.io/badge/License-MIT-blue.svg)](https://opensource.org/licenses/MIT)
[![Skills: 18](https://img.shields.io/badge/skills-18-brightgreen.svg)]()
[![Compatible with: Claude Code, Cursor, Copilot](https://img.shields.io/badge/compatible_with-Claude_Code_Cursor_Copilot-blueviolet.svg)]()

**18 production-grade AI skills · Unified format · Instant npx installation**

[Get Started](#quick-start) · [Available Packs](#available-packs) · [Contributing](#adding-a-new-pack)

---

## Give any AI agent the skills of a senior developer

Your AI agent knows how to code, but it doesn't know the specific nuances of your stack, your company's best practices, or how to use specialized tools—unless you give it those skills.

This repo contains **18 structured AI skill packs** from top open-source repositories. Every skill is normalized into a unified format, making it instantly compatible with Claude Code, Cursor, GitHub Copilot, Windsurf, OpenCode, Codex, and Agy.

## Quick start

The fastest way to give your agent superpowers is via `npx` (No cloning required):

```bash
# Option 1: npx (recommended)
npx z0team/skills-vault
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

| Pack Name | Description | Source |
|---|---|---|
| `AgricIDaniel__claude-seo` | ![Claude SEO cover: a Claude Code command palette with /seo audit, schema, ge... | [Original Repo](https://github.com/AgricIDaniel/claude-seo) |
| `addyosmani__agent-skills` | **Production-grade engineering skills for AI coding agents.** | [Original Repo](https://github.com/addyosmani/agent-skills) |
| `affaan-m__ecc` | **Language:** English   [Português (Brasil)](docs/pt-BR/README.md)   [简体中文](R... | [Original Repo](https://github.com/affaan-m/ecc) |
| `anthropics__skill-creator` |  | [Original Repo](https://github.com/anthropics/skills/tree/main/skills/skill-creator) |
| `blader__humanizer` |  | [Original Repo](https://github.com/blader/humanizer) |
| `colbymchenry__codegraph` | Already installed? Run `codegraph upgrade` to update in place. | [Original Repo](https://github.com/colbymchenry/codegraph) |
| `garrytan__gstack` |  | [Original Repo](https://github.com/garrytan/gstack) |
| `hardikpandya__stop-slop` |  | [Original Repo](https://github.com/hardikpandya/stop-slop) |
| `hesamsheikh__octogent` | <img width=1500 height=500 alt=Octogent header src=./static/images/octogent-h... | [Original Repo](https://github.com/hesamsheikh/octogent) |
| `mattpocock__grill-me` |  | [Original Repo](https://github.com/mattpocock/skills/tree/main/skills/productivity/grill-me) |
| `mksglu__context-mode` | **The other half of the context problem.** | [Original Repo](https://github.com/mksglu/context-mode) |
| `mukul975__Anthropic-Cybersecurity-Skills` | <img src=assets/banner.png alt=Anthropic Cybersecurity Skills width=100%> | [Original Repo](https://github.com/mukul975/Anthropic-Cybersecurity-Skills) |
| `nextlevelbuilder__ui-ux-pro-max-skill` | <a href=https://github.com/nextlevelbuilder/ui-ux-pro-max-skill/releases><img... | [Original Repo](https://github.com/nextlevelbuilder/ui-ux-pro-max-skill) |
| `obra__Superpowers` | Superpowers is a complete software development methodology for your coding ag... | [Original Repo](https://github.com/obra/Superpowers) |
| `open-gsd__gsd-core` | **English** · [Português](README.pt-BR.md) · [简体中文](README.zh-CN.md) · [日本語](... | [Original Repo](https://github.com/open-gsd/gsd-core) |
| `thedotmack__claude-mem` | <a href=https://github.com/thedotmack/claude-mem> | [Original Repo](https://github.com/thedotmack/claude-mem) |
| `uditgoenka__autoresearch` | **Turn [Claude Code](https://docs.anthropic.com/en/docs/claude-code), [OpenCo... | [Original Repo](https://github.com/uditgoenka/autoresearch) |
| `zarazhangrui__frontend-slides` |  | [Original Repo](https://github.com/zarazhangrui/frontend-slides) |


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

## Contributing

Want to add your favorite repository to the Vault? We welcome contributions! 

1. **Open an Issue:** Submit a link to the repository you want us to ingest.
2. **Automated Pipeline:** Our maintainers will run the ingestion pipeline (`scripts/ingest_external.py`) to normalize and publish the skills across all agent formats.

## License

Each pack retains its original license from its source repository. Please check the `pack.meta.json` inside each pack's directory for specific license notes before using third-party skills in commercial projects.
