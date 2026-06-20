#!/usr/bin/env python3
"""
ingest_external.py — завантажує 18 джерел скілів, створює pack.meta.json 
та генерує SKILL.md обгортку, якщо її немає.
"""

import subprocess
import shutil
import json
import urllib.request
from pathlib import Path
from datetime import datetime, timezone
import re
import sys

ROOT = Path(__file__).resolve().parent.parent
PACKS_DIR = ROOT / "packs"
TMP_DIR = ROOT / "tmp_ingest"

SOURCES = [
    "https://github.com/addyosmani/agent-skills",
    "https://github.com/colbymchenry/codegraph",
    "https://github.com/zarazhangrui/frontend-slides",
    "https://github.com/blader/humanizer",
    "https://github.com/affaan-m/ecc",
    "https://github.com/anthropics/skills/tree/main/skills/skill-creator",
    "https://github.com/obra/Superpowers",
    "https://github.com/open-gsd/gsd-core",
    "https://github.com/mksglu/context-mode",
    "https://github.com/thedotmack/claude-mem",
    "https://github.com/AgricIDaniel/claude-seo",
    "https://github.com/nextlevelbuilder/ui-ux-pro-max-skill",
    "https://github.com/mattpocock/skills/tree/main/skills/productivity/grill-me", # Fixed from blob to tree
    "https://github.com/garrytan/gstack",
    "https://github.com/mukul975/Anthropic-Cybersecurity-Skills",
    "https://github.com/uditgoenka/autoresearch",
    "https://github.com/hardikpandya/stop-slop",
    "https://github.com/hesamsheikh/octogent"
]

def run(cmd, cwd=None, check=True):
    return subprocess.run(cmd, cwd=cwd, shell=True, text=True, capture_output=True, check=check)

def parse_url(url: str):
    # Extracts author, repo, and subpath from GitHub URL
    m = re.match(r"https://github\.com/([^/]+)/([^/]+)(?:/(?:tree|blob)/[^/]+/(.+))?", url)
    if not m:
        raise ValueError(f"Invalid GitHub URL: {url}")
    author = m.group(1)
    repo = m.group(2)
    subpath = m.group(3)
    return author, repo, subpath

def ensure_skill_wrapper(skill_dir: Path, pack_id: str, author: str, repo: str):
    """
    If no SKILL.md or proper structure exists, wrap it.
    But many repos have skills nested differently. 
    If a repo already has SKILL.md somewhere, we shouldn't necessarily wrap the whole repo.
    Actually, the instruction says: "Якщо формат не стандартний (немає SKILL.md з фронтматером) - 
    створи SKILL.md-обгортку: name, description (з README)".
    To be safe, we will just create `skills/<pack_id>/SKILL.md` inside the pack dir if it lacks one.
    """
    # Look for existing SKILL.md anywhere
    existing = list(skill_dir.rglob("SKILL.md"))
    has_valid_skill = False
    
    for md in existing:
        text = md.read_text(encoding="utf-8-sig", errors="replace")
        if re.search(r"^---.*?\nname:.*?\n---", text, re.DOTALL | re.IGNORECASE):
            has_valid_skill = True
            break
            
    if has_valid_skill:
        return
        
    print(f"  [!] No valid SKILL.md found for {pack_id}, creating wrapper...")
    
    # Try to extract description from README
    readme = None
    for r in ["README.md", "readme.md", "README.txt"]:
        p = skill_dir / r
        if p.exists():
            readme = p
            break
            
    desc = "No description provided."
    if readme:
        content = readme.read_text(encoding="utf-8-sig", errors="replace")
        # Grab first paragraph after headers
        lines = content.splitlines()
        for line in lines:
            line = line.strip()
            if line and not line.startswith("#") and not line.startswith("[") and len(line) > 20:
                desc = line[:200] + "..." if len(line) > 200 else line
                break
                
    skills_folder = skill_dir / "skills" / pack_id
    skills_folder.mkdir(parents=True, exist_ok=True)
    
    wrapper = f"""---
name: {pack_id}
description: "{desc.replace('"', '')}"
---

# {pack_id}

This skill was imported from {author}/{repo}.
Please refer to the original files in this directory for instructions.
"""
    (skills_folder / "SKILL.md").write_text(wrapper, encoding="utf-8")


def process_source(url):
    author, repo, subpath = parse_url(url)
    repo_url = f"https://github.com/{author}/{repo}.git"
    
    pack_name = repo if not subpath else Path(subpath).name
    pack_id = f"{author}__{pack_name}"
    
    print(f"\n📥 Processing {pack_id}...")
    
    tmp_repo_dir = TMP_DIR / pack_id
    if tmp_repo_dir.exists():
        shutil.rmtree(tmp_repo_dir)
        
    # Clone sparse
    print(f"  > Cloning {repo_url} ...")
    try:
        run(f"git clone --depth 1 --filter=blob:none --sparse {repo_url} {tmp_repo_dir}")
        if subpath:
            print(f"  > Sparse checkout {subpath} ...")
            run(f"git sparse-checkout set {subpath}", cwd=tmp_repo_dir)
    except subprocess.CalledProcessError as e:
        print(f"  ❌ Failed to clone {repo_url}:\n{e.stderr}")
        return False
        
    # Determine the actual source folder
    source_folder = tmp_repo_dir / subpath if subpath else tmp_repo_dir
    if not source_folder.exists():
        print(f"  ❌ Subpath {subpath} not found in repo.")
        return False
        
    # Copy to packs/
    target_pack_dir = PACKS_DIR / pack_id
    if target_pack_dir.exists():
        shutil.rmtree(target_pack_dir)
    
    # We use shutil.copytree but ignore .git
    shutil.copytree(source_folder, target_pack_dir, ignore=shutil.ignore_patterns(".git"), symlinks=True)
    
    ensure_skill_wrapper(target_pack_dir, pack_name, author, repo)
    
    # Create pack.meta.json
    fetched_at = datetime.now(timezone.utc).isoformat() + "Z"
    meta = {
        "id": pack_id,
        "source": url,
        "license": None,
        "fetched_at": fetched_at,
        "type": "skill",
        "agents": ["claude-code", "cursor", "generic"]
    }
    
    if "mukul975/Anthropic-Cybersecurity-Skills" in url:
        meta["mcp_servers"] = [
            { "name": "21st-dev", "command": "npx -y @21st-dev/cli@latest" }
        ]
        
    # Try to find LICENSE
    for l in ["LICENSE", "LICENSE.md", "LICENSE.txt"]:
        if (target_pack_dir / l).exists():
            meta["license"] = "Found in repository"
            break
            
    (target_pack_dir / "pack.meta.json").write_text(json.dumps(meta, indent=2), encoding="utf-8")
    
    print(f"  ✅ Saved to packs/{pack_id}")
    return True

def main():
    if TMP_DIR.exists():
        shutil.rmtree(TMP_DIR)
    TMP_DIR.mkdir(parents=True)
    PACKS_DIR.mkdir(parents=True, exist_ok=True)
    
    success = 0
    for src in SOURCES:
        if process_source(src.replace("blob/main", "tree/main")):
            success += 1
            
    shutil.rmtree(TMP_DIR)
    print(f"\n🎉 Finished! Processed {success}/{len(SOURCES)} sources.")

if __name__ == "__main__":
    main()
