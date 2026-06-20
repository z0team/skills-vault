#!/usr/bin/env python3
"""
build_registry.py — сканує packs/ і генерує registry.json: єдиний
машинно-читабельний індекс усіх паків і скілів у репозиторії.

Запускати після кожного ingest.sh (або через git pre-commit hook).
"""

from __future__ import annotations
import json
import re
import sys
from pathlib import Path
from datetime import datetime, timezone

ROOT = Path(__file__).resolve().parent.parent
PACKS_DIR = ROOT / "packs"
REGISTRY_PATH = ROOT / "registry.json"


def parse_frontmatter(skill_md: Path) -> dict:
    text = skill_md.read_text(encoding="utf-8", errors="replace")
    m = re.match(r"^---\s*\n(.*?)\n---\s*\n", text, re.DOTALL)
    if not m:
        return {}
    fm = {}
    for line in m.group(1).splitlines():
        if ":" in line:
            k, _, v = line.partition(":")
            fm[k.strip()] = v.strip().strip('"').strip("'")
    return fm


def main():
    if not PACKS_DIR.exists():
        print("packs/ не існує — нічого індексувати.", file=sys.stderr)
        sys.exit(0)

    packs = []
    total_skills = 0

    for author_dir in sorted(p for p in PACKS_DIR.iterdir() if p.is_dir()):
        for pack_dir in sorted(p for p in author_dir.iterdir() if p.is_dir()):
            pack_json_path = pack_dir / "pack.json"
            pack_meta = {}
            if pack_json_path.exists():
                try:
                    pack_meta = json.loads(pack_json_path.read_text(encoding="utf-8"))
                except json.JSONDecodeError:
                    pack_meta = {}

            skills_dir = pack_dir / "skills"
            skills = []
            if skills_dir.exists():
                for skill_dir in sorted(p for p in skills_dir.iterdir() if p.is_dir()):
                    skill_md = skill_dir / "SKILL.md"
                    if not skill_md.exists():
                        continue
                    fm = parse_frontmatter(skill_md)
                    skills.append({
                        "name": fm.get("name", skill_dir.name),
                        "description": fm.get("description", ""),
                        "path": str(skill_md.relative_to(ROOT)),
                        "license": fm.get("license"),
                    })

            total_skills += len(skills)
            packs.append({
                "author": author_dir.name,
                "pack_name": pack_dir.name,
                "source_url": pack_meta.get("source_url"),
                "ingested_at": pack_meta.get("ingested_at"),
                "license_note": pack_meta.get("license_note"),
                "skill_count": len(skills),
                "skills": skills,
            })

    registry = {
        "generated_at": datetime.now(timezone.utc).strftime("%Y-%m-%dT%H:%M:%SZ"),
        "pack_count": len(packs),
        "skill_count": total_skills,
        "packs": packs,
    }

    REGISTRY_PATH.write_text(json.dumps(registry, indent=2, ensure_ascii=False) + "\n", encoding="utf-8")
    print(f"✅ registry.json оновлено: {len(packs)} пак(ів), {total_skills} скіл(ів)")


if __name__ == "__main__":
    main()
