#!/usr/bin/env bash
# build-dist.sh — генерує структуру dist/ для інсталятора get.sh

set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
DIST_DIR="$ROOT_DIR/dist"
PACKS_DIR="$ROOT_DIR/packs"
CONVERT="$ROOT_DIR/scripts/convert.py"

echo "📦 Генеруємо dist/ ..."
python3 -c "
import shutil, os, stat
def onerror(func, path, exc_info):
    try: os.chmod(path, stat.S_IRWXU); func(path)
    except: pass
for d in ['dist', 'skills', '.claude-plugin', '.cursor-plugin', '.codex-plugin', '.opencode', '.windsurf-plugin', '.roo', '.prompts', '.zed', '.trae']:
    if os.path.exists(os.path.join('$ROOT_DIR', d)):
        shutil.rmtree(os.path.join('$ROOT_DIR', d), onerror=onerror)
"

mkdir -p "$DIST_DIR"
mkdir -p "$ROOT_DIR/skills"
chmod u+w "$DIST_DIR" "$ROOT_DIR/skills" 2>/dev/null || true

AGENTS=("claude-code" "cursor" "copilot" "windsurf" "opencode" "codex" "agy" "agents-md" "generic" "roo" "continue" "zed" "trae")

CMDS_FILE=$(mktemp)

for pack_dir in "$PACKS_DIR"/*; do
    [ -d "$pack_dir" ] || continue
    pack_id=$(basename "$pack_dir")
    
    # Process skills for npx
    find "$pack_dir" -name "SKILL.md" 2>/dev/null | while read -r skill_md; do
        skill_folder=$(basename "$(dirname "$skill_md")")
        if [ "$skill_folder" = "$pack_id" ] || [ "$skill_folder" = "skills" ] || [ "$skill_folder" = "." ]; then
            skill_folder="${pack_id}"
        else
            skill_folder="${pack_id}__${skill_folder}"
        fi
        
        mkdir -p "$ROOT_DIR/skills/$skill_folder"
        cp "$skill_md" "$ROOT_DIR/skills/$skill_folder/SKILL.md"
        
        # Add python conversion jobs
        for agent in "${AGENTS[@]}"; do
            OUT_DIR="$DIST_DIR/$pack_id/$agent"
            echo "mkdir -p \"$OUT_DIR\" && python3 \"$CONVERT\" \"$skill_md\" --target \"$agent\" --out \"$OUT_DIR\" >/dev/null 2>&1" >> "$CMDS_FILE"
        done
    done || true
done

echo "🚀 Конвертуємо скіли паралельно (це може зайняти хвилину)..."
while IFS= read -r cmd; do
    eval "$cmd" &
    # Check number of running jobs
    while [ $(jobs -r | wc -l) -ge 16 ]; do
        sleep 0.1
    done
done < "$CMDS_FILE"
wait
rm -f "$CMDS_FILE"

echo "🔗 Копіюємо всі правила в кореневі папки..."
mkdir -p "$ROOT_DIR/.claude-plugin" "$ROOT_DIR/.cursor-plugin" "$ROOT_DIR/.codex-plugin" "$ROOT_DIR/.opencode" "$ROOT_DIR/.windsurf-plugin" "$ROOT_DIR/.roo" "$ROOT_DIR/.prompts" "$ROOT_DIR/.zed" "$ROOT_DIR/.trae"

# Aggregation logic
for pack_dir in "$DIST_DIR"/*; do
    if [ -d "$pack_dir/claude-code" ]; then cp -R "$pack_dir/claude-code/"* "$ROOT_DIR/.claude-plugin/" 2>/dev/null || true; fi
    if [ -d "$pack_dir/cursor" ]; then cp -R "$pack_dir/cursor/"* "$ROOT_DIR/.cursor-plugin/" 2>/dev/null || true; fi
    if [ -d "$pack_dir/codex" ]; then cp -R "$pack_dir/codex/"* "$ROOT_DIR/.codex-plugin/" 2>/dev/null || true; fi
    if [ -d "$pack_dir/opencode" ]; then cp -R "$pack_dir/opencode/"* "$ROOT_DIR/.opencode/" 2>/dev/null || true; fi
    if [ -d "$pack_dir/windsurf" ]; then cp -R "$pack_dir/windsurf/"* "$ROOT_DIR/.windsurf-plugin/" 2>/dev/null || true; fi
    if [ -d "$pack_dir/roo" ]; then cp -R "$pack_dir/roo/"* "$ROOT_DIR/.roo/" 2>/dev/null || true; fi
    if [ -d "$pack_dir/continue" ]; then cp -R "$pack_dir/continue/"* "$ROOT_DIR/.prompts/" 2>/dev/null || true; fi
    if [ -d "$pack_dir/zed" ]; then cp -R "$pack_dir/zed/"* "$ROOT_DIR/.zed/" 2>/dev/null || true; fi
    if [ -d "$pack_dir/trae" ]; then cp -R "$pack_dir/trae/"* "$ROOT_DIR/.trae/" 2>/dev/null || true; fi
done

echo "📦 Створюємо архів dist.tar.gz ..."
cp "$ROOT_DIR/registry.json" "$DIST_DIR/registry.json"

echo "🗜️ Створюємо dist.tar.gz ..."
cd "$DIST_DIR"
tar -czf dist.tar.gz *
cd "$ROOT_DIR"

echo "✅ Успішно згенеровано $DIST_DIR/dist.tar.gz"
