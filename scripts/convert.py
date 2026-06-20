#!/usr/bin/env python3
"""
convert.py — перетворює internal-format скіл (SKILL.md, agentskills.io
стандарт) у формат, який очікує конкретний AI-агент.

Internal format (джерело правди):
    packs/<author>/<pack-name>/skills/<skill-name>/SKILL.md
        ---
        name: skill-name
        description: ...
        license: ...           (опційно)
        allowed-tools: ...     (опційно, Claude Code-специфічно)
        ---
        <markdown body>

Підтримувані цілі (--target):
    claude-code   -> копія SKILL.md як є, директорія <skill-name>/
    cursor        -> .cursor/rules/<skill-name>.mdc (description+globs+alwaysApply)
    copilot       -> .github/instructions/<skill-name>.instructions.md
    windsurf      -> .windsurf/rules/<skill-name>.md
    agents-md     -> append-блок у AGENTS.md (для Codex/OpenClaw/універсальних агентів)
    generic       -> сирий SKILL.md (працює для будь-якого агента, що підтримує agentskills.io)

Дизайн: SKILL.md лишається єдиним джерелом правди. Усі інші формати
ГЕНЕРУЮТЬСЯ з нього, ніколи не редагуються вручну.
"""

from __future__ import annotations
import argparse
import re
import sys
import shutil
from pathlib import Path
from typing import Optional
import yaml  # PyYAML


class SkillMeta:
    def __init__(self, frontmatter: dict, body: str, skill_dir: Path):
        self.name: str = frontmatter.get("name", skill_dir.name)
        self.description: str = frontmatter.get("description", "").strip()
        self.license: Optional[str] = frontmatter.get("license")
        self.allowed_tools: Optional[str] = frontmatter.get("allowed-tools")
        self.globs: Optional[str] = frontmatter.get("globs")  # якщо автор уже задав
        self.always_apply: bool = bool(frontmatter.get("always-apply", False))
        self.version: Optional[str] = frontmatter.get("version")
        self.author: Optional[str] = frontmatter.get("author")
        self.raw_frontmatter = frontmatter
        self.body = body
        self.skill_dir = skill_dir


def parse_skill_md(path: Path) -> SkillMeta:
    text = path.read_text(encoding="utf-8-sig")
    m = re.match(r"^---\s*\n(.*?)\n---\s*\n?(.*)$", text, re.DOTALL)
    if not m:
        # Відсутній frontmatter — генеруємо базовий
        fm = {
            "name": path.parent.name,
            "description": "(Опис відсутній у джерелі)"
        }
        return SkillMeta(fm, text, path.parent)
        
    fm_raw, body = m.group(1), m.group(2)
    frontmatter = yaml.safe_load(fm_raw) or {}
    if "name" not in frontmatter:
        frontmatter["name"] = path.parent.name
    if "description" not in frontmatter:
        frontmatter["description"] = "(Опис відсутній у джерелі)"
    return SkillMeta(frontmatter, body, path.parent)


def first_sentence(text: str, max_len: int = 160) -> str:
    text = " ".join(text.split())
    m = re.search(r"^(.{1,%d}?[.!?])\s" % max_len, text + " ")
    candidate = m.group(1) if m else text[:max_len]
    return candidate.strip()


def _copy_skill_dir(skill: SkillMeta, dest_dir: Path) -> Path:
    dest_dir.mkdir(parents=True, exist_ok=True)
    for item in skill.skill_dir.iterdir():
        target = dest_dir / item.name
        if item.is_symlink():
            if target.is_symlink() or target.exists():
                target.unlink()
            shutil.copy2(item, target, follow_symlinks=False)
        elif item.is_dir():
            shutil.copytree(item, target, dirs_exist_ok=True, symlinks=True)
        else:
            shutil.copy2(item, target)
    return dest_dir / "SKILL.md"


# ---------------------------------------------------------------------------
# Target: Claude Code — SKILL.md лишається SKILL.md, просто копіюється
# ---------------------------------------------------------------------------
def to_claude_code(skill: SkillMeta, out_root: Path) -> Path:
    return _copy_skill_dir(skill, out_root / "skills" / skill.name)


# ---------------------------------------------------------------------------
# Target: OpenCode — .opencode/skills/<name>
# ---------------------------------------------------------------------------
def to_opencode(skill: SkillMeta, out_root: Path) -> Path:
    return _copy_skill_dir(skill, out_root / ".opencode" / "skills" / skill.name)


# ---------------------------------------------------------------------------
# Target: Codex — .codex/skills/<name>
# ---------------------------------------------------------------------------
def to_codex(skill: SkillMeta, out_root: Path) -> Path:
    return _copy_skill_dir(skill, out_root / ".codex" / "skills" / skill.name)


# ---------------------------------------------------------------------------
# Target: Agy — .agy/rules/<name>
# ---------------------------------------------------------------------------
def to_agy(skill: SkillMeta, out_root: Path) -> Path:
    return _copy_skill_dir(skill, out_root / ".agy" / "rules" / skill.name)


# ---------------------------------------------------------------------------
# Target: Cursor — .cursor/rules/<name>.mdc
# Cursor підтримує SKILL.md нативно (description-driven), АЛЕ для проєктів,
# де хочуть file-scoped автозавантаження, генеруємо .mdc rule-обгортку.
# ---------------------------------------------------------------------------
def to_cursor(skill: SkillMeta, out_root: Path) -> Path:
    rules_dir = out_root / ".cursor" / "rules"
    rules_dir.mkdir(parents=True, exist_ok=True)

    fm_lines = ["---"]
    desc = skill.description.replace("\n", " ").replace('"', "'")
    fm_lines.append(f'description: "{desc}"')
    if skill.globs:
        fm_lines.append(f"globs: {skill.globs}")
    fm_lines.append(f"alwaysApply: {str(skill.always_apply).lower()}")
    fm_lines.append("---")

    header = f"# {skill.name}\n\n"
    src_note = ""
    if skill.author:
        src_note = f"> Конвертовано з SKILL.md (автор: {skill.author}). Джерело правди — packs/.../SKILL.md.\n\n"

    content = "\n".join(fm_lines) + "\n\n" + header + src_note + skill.body
    dest = rules_dir / f"{skill.name}.mdc"
    dest.write_text(content, encoding="utf-8")

    # supporting файли (скрипти, шаблони) кладемо поруч у .cursor/rules/<name>/
    extra_dir = rules_dir / skill.name
    has_extra = any(p.name != "SKILL.md" for p in skill.skill_dir.iterdir())
    if has_extra:
        extra_dir.mkdir(parents=True, exist_ok=True)
        for item in skill.skill_dir.iterdir():
            if item.name == "SKILL.md":
                continue
            target = extra_dir / item.name
            if item.is_symlink():
                if target.is_symlink() or target.exists():
                    target.unlink()
                shutil.copy2(item, target, follow_symlinks=False)
            elif item.is_dir():
                shutil.copytree(item, target, dirs_exist_ok=True, symlinks=True)
            else:
                shutil.copy2(item, target)
    return dest


# ---------------------------------------------------------------------------
# Target: GitHub Copilot — .github/instructions/<name>.instructions.md
# ---------------------------------------------------------------------------
def to_copilot(skill: SkillMeta, out_root: Path) -> Path:
    dest_dir = out_root / ".github" / "instructions"
    dest_dir.mkdir(parents=True, exist_ok=True)
    fm = "---\n"
    if skill.globs:
        fm += f"applyTo: \"{skill.globs}\"\n"
    else:
        fm += "applyTo: \"**\"\n"
    fm += "---\n\n"
    content = fm + f"# {skill.name}\n\n{skill.description}\n\n{skill.body}"
    dest = dest_dir / f"{skill.name}.instructions.md"
    dest.write_text(content, encoding="utf-8")
    return dest


# ---------------------------------------------------------------------------
# Target: Windsurf — .windsurf/rules/<name>.md
# ---------------------------------------------------------------------------
def to_windsurf(skill: SkillMeta, out_root: Path) -> Path:
    dest_dir = out_root / ".windsurf" / "rules"
    dest_dir.mkdir(parents=True, exist_ok=True)
    content = f"# {skill.name}\n\n{skill.description}\n\n{skill.body}"
    dest = dest_dir / f"{skill.name}.md"
    dest.write_text(content, encoding="utf-8")
    return dest


# ---------------------------------------------------------------------------
# Target: AGENTS.md — універсальний append-блок (Codex, OpenClaw, інші
# агенти, що читають AGENTS.md як конвенцію)
# ---------------------------------------------------------------------------
def to_agents_md(skill: SkillMeta, out_root: Path) -> Path:
    dest = out_root / "AGENTS.md"
    marker_start = f"<!-- skill:{skill.name}:start -->"
    marker_end = f"<!-- skill:{skill.name}:end -->"
    block = (
        f"{marker_start}\n"
        f"## Skill: {skill.name}\n\n"
        f"{skill.description}\n\n"
        f"{skill.body}\n"
        f"{marker_end}\n"
    )
    if dest.exists():
        existing = dest.read_text(encoding="utf-8")
        pattern = re.compile(
            re.escape(marker_start) + r".*?" + re.escape(marker_end) + r"\n?",
            re.DOTALL,
        )
        if pattern.search(existing):
            existing = pattern.sub(lambda m: block, existing)
        else:
            existing = existing.rstrip() + "\n\n" + block
        dest.write_text(existing, encoding="utf-8")
    else:
        dest.write_text(f"# AGENTS.md\n\n{block}", encoding="utf-8")
    return dest


# ---------------------------------------------------------------------------
# Target: generic — сирий SKILL.md, для будь-якого agentskills.io-сумісного
# агента (Gemini CLI, OpenCode, Antigravity тощо)
# ---------------------------------------------------------------------------
def to_generic(skill: SkillMeta, out_root: Path) -> Path:
    return to_claude_code(skill, out_root)

def to_roo(skill: SkillMeta, out_root: Path) -> Path:
    dest_dir = out_root / ".roo" / "rules"
    dest_dir.mkdir(parents=True, exist_ok=True)
    content = f"---\ndescription: {skill.description}\nglobs: *\n---\n\n{skill.body}"
    dest = dest_dir / f"{skill.name}.mdc"
    dest.write_text(content, encoding="utf-8")
    return dest

def to_continue(skill: SkillMeta, out_root: Path) -> Path:
    dest_dir = out_root / ".prompts"
    dest_dir.mkdir(parents=True, exist_ok=True)
    content = f"---\ndescription: {skill.description}\n---\n\n{skill.body}"
    dest = dest_dir / f"{skill.name}.prompt"
    dest.write_text(content, encoding="utf-8")
    return dest

def to_zed(skill: SkillMeta, out_root: Path) -> Path:
    dest_dir = out_root / ".zed" / "prompts"
    dest_dir.mkdir(parents=True, exist_ok=True)
    content = f"# {skill.name}\n\n{skill.description}\n\n{skill.body}"
    dest = dest_dir / f"{skill.name}.md"
    dest.write_text(content, encoding="utf-8")
    return dest

def to_trae(skill: SkillMeta, out_root: Path) -> Path:
    dest_dir = out_root / ".trae" / "rules"
    dest_dir.mkdir(parents=True, exist_ok=True)
    content = f"---\ndescription: {skill.description}\nglobs: *\n---\n\n{skill.body}"
    dest = dest_dir / f"{skill.name}.mdc"
    dest.write_text(content, encoding="utf-8")
    return dest


TARGETS = {
    "claude-code": to_claude_code,
    "cursor": to_cursor,
    "copilot": to_copilot,
    "windsurf": to_windsurf,
    "agents-md": to_agents_md,
    "generic": to_generic,
    "opencode": to_opencode,
    "codex": to_codex,
    "agy": to_agy,
    "roo": to_roo,
    "continue": to_continue,
    "zed": to_zed,
    "trae": to_trae,
}


def main():
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("skill_md", type=Path, help="Шлях до internal SKILL.md")
    ap.add_argument("--target", required=True, choices=TARGETS.keys())
    ap.add_argument("--out", type=Path, required=True, help="Коренева директорія призначення (наприклад ~/.claude або ./<project>)")
    args = ap.parse_args()

    if not args.skill_md.exists():
        print(f"❌ Не знайдено: {args.skill_md}", file=sys.stderr)
        sys.exit(1)

    try:
        skill = parse_skill_md(args.skill_md)
    except ValueError as e:
        print(f"❌ {e}", file=sys.stderr)
        sys.exit(1)

    fn = TARGETS[args.target]
    dest = fn(skill, args.out)
    print(f"✅ [{args.target}] {skill.name} -> {dest}")


if __name__ == "__main__":
    main()
