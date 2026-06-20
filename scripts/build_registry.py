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
    text = skill_md.read_text(encoding="utf-8-sig", errors="replace")
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
    
    for author_dir in sorted(p for p in PACKS_DIR.iterdir() if p.is_dir()):
        # In the new structure, packs are directly under PACKS_DIR named like author__pack
        pass

    # New parsing logic
    for pack_dir in sorted(p for p in PACKS_DIR.iterdir() if p.is_dir()):
        meta_path = pack_dir / "pack.meta.json"
        if not meta_path.exists():
            continue
            
        try:
            meta = json.loads(meta_path.read_text(encoding="utf-8"))
        except Exception:
            continue
            
        # Parse SKILL.md to get description
        skills_dir = pack_dir / "skills"
        description = meta.get("description", "")
        tags = []
        
        if skills_dir.exists():
            for skill_dir in sorted(p for p in skills_dir.iterdir() if p.is_dir()):
                skill_md = skill_dir / "SKILL.md"
                if skill_md.exists():
                    fm = parse_frontmatter(skill_md)
                    if not description:
                        description = fm.get("description", "")
                    tags.extend([t.strip() for t in fm.get("tags", "").split(",") if t.strip()])
        
        packs.append({
            "id": meta.get("id"),
            "path": f"packs/{pack_dir.name}",
            "source": meta.get("source"),
            "type": meta.get("type", "skill"),
            "description": description,
            "tags": list(set(tags)),
            "mcp_servers": meta.get("mcp_servers", [])
        })

    registry = {
        "generated_at": datetime.now(timezone.utc).strftime("%Y-%m-%dT%H:%M:%SZ"),
        "pack_count": len(packs),
        "packs": packs,
    }

    REGISTRY_PATH.write_text(json.dumps(registry, indent=2, ensure_ascii=False) + "\n", encoding="utf-8")
    print(f"✅ registry.json оновлено: {len(packs)} пак(ів)")


if __name__ == "__main__":
    main()
