#!/usr/bin/env bash
# export_all.sh — автоматично генерує всі можливі формати скілів у папку dist/
# для того, щоб користувачі могли просто копіювати їх без запуску інсталятора.

set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
DIST_DIR="$ROOT_DIR/dist"

echo "📦 Експортуємо всі скіли у $DIST_DIR ..."

AGENTS=("claude-code" "cursor" "copilot" "windsurf" "opencode" "codex" "agy" "agents-md" "generic")

rm -rf "$DIST_DIR"
mkdir -p "$DIST_DIR"

for agent in "${AGENTS[@]}"; do
  echo "⏳ Генеруємо для $agent..."
  "$ROOT_DIR/scripts/install.sh" --all --agent "$agent" --scope local --project "$DIST_DIR/$agent" >/dev/null
done

echo "✅ Експорт успішно завершено! Усі готові скіли знаходяться у папці dist/"
