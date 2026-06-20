# skills-vault

Особисте сховище AI-агентських skill-паків від різних авторів, нормалізованих
в єдиний внутрішній формат і готових до встановлення в **Claude Code, Cursor,
GitHub Copilot, Windsurf** та будь-який агент, що читає `AGENTS.md` (Codex,
OpenClaw тощо).

## Як це влаштовано

```
skills-vault/
├── packs/
│   └── <author>/
│       └── <pack-name>/
│           ├── pack.json              # джерело, ліцензія, дата ingest
│           └── skills/
│               └── <skill-name>/
│                   ├── SKILL.md       # internal format (agentskills.io)
│                   ├── scripts/       # опційно
│                   ├── references/    # опційно
│                   └── templates/     # опційно
├── registry.json                      # авто-індекс усіх паків/скілів
├── scripts/
│   ├── ingest.sh                      # скачує + нормалізує новий пак
│   ├── install.sh                     # ставить скіли під конкретний агент
│   ├── convert.py                     # SKILL.md -> формат агента
│   └── build_registry.py              # перебудовує registry.json
└── README.md
```

**Internal format = `SKILL.md`** (YAML frontmatter `name` + `description`,
далі markdown-тіло) — це відкритий стандарт [agentskills.io](https://agentskills.io),
який нативно читають Claude Code, Cursor, Codex, Gemini CLI та десятки інших
агентів. Усе, що приходить в інших форматах (`.cursor/rules/*.mdc`,
`.cursorrules`, кастомні), при ingest конвертується в `SKILL.md`. Інші
формати (наприклад file-scoped `.mdc` з `globs`) **генеруються** з нього при
встановленні — вручну ніхто нічого не редагує, крім самого `SKILL.md`.

## Додати новий пак

```bash
./scripts/ingest.sh https://github.com/owner/repo
./scripts/ingest.sh https://github.com/owner/repo --name custom-pack-name --author custom-author
./scripts/build_registry.py
```

Дивись також [`docs/AGENT_INGEST_PROMPT.md`](docs/AGENT_INGEST_PROMPT.md) —
готовий промпт, який можна віддати Claude Code/іншому агенту: вставляєш
посилання, агент сам клонує, нормалізує, перевіряє якість і комітить.

## Встановити скіли

```bash
# інтерактивно (запитає що / для якого агента / global чи local)
./scripts/install.sh

# конкретний скіл, конкретний агент, глобально
./scripts/install.sh --skill pdf-forms --agent claude-code --scope global

# весь пак, в конкретний проєкт
./scripts/install.sh --pack obra/superpowers --agent cursor --scope local --project ~/dev/my-app

# взагалі все
./scripts/install.sh --all --agent claude-code --scope global

# глянути що є в наявності
./scripts/install.sh --list
```

### Куди ставиться, залежно від агента/scope

| Агент | global | local |
|---|---|---|
| `claude-code` | `~/.claude/skills/` | `<project>/.claude/skills/` |
| `cursor` | — (не підтримує) | `<project>/.cursor/rules/` |
| `copilot` | `~/.claude/skills/` (fallback) | `<project>/.github/instructions/` |
| `windsurf` | `~/.claude/skills/` (fallback) | `<project>/.windsurf/rules/` |
| `agents-md` | `~/.claude/AGENTS.md` | `<project>/AGENTS.md` |
| `generic` | сирий `SKILL.md`, копія куди вкажеш | те саме |

## Реєстр

`registry.json` — машинно-читабельний індекс всього репо (автор, пак,
скіл, опис, шлях, ліцензія). Оновлюється `scripts/build_registry.py`,
читається `install.sh` для пошуку.

## Ліцензії

Кожен пак зберігає `license_note` у своєму `pack.json` з джерела. Перед
використанням стороннього скіла в комерційному проєкті — перевір ліцензію
оригінального репо вручну.
