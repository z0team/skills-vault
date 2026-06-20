#!/usr/bin/env bash
# ingest.sh — скачує зовнішній skill-пак за посиланням і нормалізує його
# в internal-формат skills-vault (packs/<author>/<pack-name>/skills/<skill>/SKILL.md).
#
# Використання:
#   ./scripts/ingest.sh <github-url> [--name <pack-name>] [--author <author>]
#
# Приклади:
#   ./scripts/ingest.sh https://github.com/obra/superpowers
#   ./scripts/ingest.sh https://github.com/anthropics/skills --name anthropic-official
#
# Що робить:
#   1. git clone --depth 1 джерела у тимчасову директорію
#   2. Шукає всі SKILL.md у репо (будь-яка глибина вкладеності)
#   3. Якщо знайдено формат .cursor/rules/*.mdc без SKILL.md — конвертує назад
#      у SKILL.md (best-effort: description з frontmatter, тіло як є)
#   4. Копіює кожен скіл у packs/<author>/<pack-name>/skills/<skill-name>/
#   5. Створює/оновлює pack.json з метаданими джерела
#   6. Прибирає тимчасову директорію

set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
PACKS_DIR="$ROOT_DIR/packs"

URL=""
NAME_OVERRIDE=""
AUTHOR_OVERRIDE=""

err()  { echo "❌ $*" >&2; }
info() { echo "ℹ️  $*"; }
ok()   { echo "✅ $*"; }

while [ $# -gt 0 ]; do
  case "$1" in
    --name) NAME_OVERRIDE="$2"; shift 2 ;;
    --author) AUTHOR_OVERRIDE="$2"; shift 2 ;;
    -h|--help) sed -n '2,20p' "$0"; exit 0 ;;
    *)
      if [ -z "$URL" ]; then URL="$1"; shift
      else err "Невідома опція: $1"; exit 1; fi ;;
  esac
done

[ -z "$URL" ] && { err "Потрібен URL. Приклад: ./scripts/ingest.sh https://github.com/owner/repo"; exit 1; }

# ---------- розбір URL: owner/repo (+ опційний subpath) ------------------
# Підтримує:
#   https://github.com/owner/repo
#   https://github.com/owner/repo/tree/main/path/to/subdir
CLEAN_URL="${URL%/}"
if [[ "$CLEAN_URL" =~ github\.com/([^/]+)/([^/]+)(/tree/[^/]+/(.+))? ]]; then
  GH_OWNER="${BASH_REMATCH[1]}"
  GH_REPO="${BASH_REMATCH[2]%.git}"
  GH_SUBPATH="${BASH_REMATCH[4]:-}"
else
  err "Поки що підтримуються тільки github.com URL. Отримано: $URL"
  exit 1
fi

AUTHOR="${AUTHOR_OVERRIDE:-$GH_OWNER}"
PACK_NAME="${NAME_OVERRIDE:-$GH_REPO}"

REPO_CLONE_URL="https://github.com/$GH_OWNER/$GH_REPO.git"
TMP_DIR="$(mktemp -d)"
trap 'rm -rf "$TMP_DIR"' EXIT

info "Клоную $REPO_CLONE_URL ..."
git clone --depth 1 --quiet "$REPO_CLONE_URL" "$TMP_DIR/repo" \
  || { err "Не вдалося склонувати репозиторій. Перевір URL і мережевий доступ."; exit 1; }

SEARCH_ROOT="$TMP_DIR/repo"
if [ -n "$GH_SUBPATH" ]; then
  SEARCH_ROOT="$TMP_DIR/repo/$GH_SUBPATH"
fi

if [ ! -d "$SEARCH_ROOT" ]; then
  err "Підшлях не знайдено в репо: $GH_SUBPATH"
  exit 1
fi

# ---------- пошук SKILL.md ------------------------------------------------
SKILL_FILES=()
while IFS= read -r line; do
  [ -n "$line" ] && SKILL_FILES+=("$line")
done < <(find "$SEARCH_ROOT" -name "SKILL.md" -not -path "*/node_modules/*" 2>/dev/null || true)

if [ "${#SKILL_FILES[@]}" -eq 0 ]; then
  info "SKILL.md не знайдено напряму. Шукаю .mdc / .cursor/rules для конвертації..."
  MDC_FILES=()
  while IFS= read -r line; do
    [ -n "$line" ] && MDC_FILES+=("$line")
  done < <(find "$SEARCH_ROOT" -name "*.mdc" -not -path "*/node_modules/*" 2>/dev/null || true)
  if [ "${#MDC_FILES[@]}" -eq 0 ]; then
    err "Не знайдено жодного скіла (ні SKILL.md, ні .mdc) у $URL"
    err "Перевір посилання вручну — можливо, формат нестандартний."
    exit 1
  fi
  info "Знайдено ${#MDC_FILES[@]} .mdc файл(ів) — буде best-effort конвертація в SKILL.md."
fi

DEST_SKILLS_DIR="$PACKS_DIR/$AUTHOR/$PACK_NAME/skills"
mkdir -p "$DEST_SKILLS_DIR"

INSTALLED_COUNT=0

# ---------- копіювання канонічних SKILL.md --------------------------------
for f in "${SKILL_FILES[@]:-}"; do
  [ -z "$f" ] && continue
  SKILL_DIR="$(dirname "$f")"
  SKILL_NAME="$(basename "$SKILL_DIR")"
  # Якщо назва директорії неінформативна (напр. "skill"), пробуємо взяти name: з frontmatter
  FM_NAME=$(grep -m1 '^name:' "$f" | sed -E 's/^name:\s*//; s/^"//; s/"$//' || true)
  if [ -n "$FM_NAME" ]; then
    SKILL_NAME="$FM_NAME"
  fi
  DEST="$DEST_SKILLS_DIR/$SKILL_NAME"
  mkdir -p "$DEST"
  cp -r "$SKILL_DIR"/. "$DEST/"
  ok "Додано скіл: $SKILL_NAME"
  INSTALLED_COUNT=$((INSTALLED_COUNT + 1))
done

# ---------- best-effort конвертація .mdc -> SKILL.md -----------------------
for f in "${MDC_FILES[@]:-}"; do
  [ -z "$f" ] && continue
  SKILL_NAME="$(basename "$f" .mdc)"
  DEST="$DEST_SKILLS_DIR/$SKILL_NAME"
  mkdir -p "$DEST"

  DESC=$(awk '/^description:/{sub(/^description:[ \t]*/,""); print; exit}' "$f" | sed -E 's/^"//; s/"$//')
  [ -z "$DESC" ] && DESC="(опис відсутній у джерелі — заповни вручну)"

  BODY=$(awk 'BEGIN{c=0} /^---$/{c++; next} c>=2{print}' "$f")

  {
    echo "---"
    echo "name: $SKILL_NAME"
    echo "description: \"$DESC\""
    echo "source: \"$URL\""
    echo "---"
    echo ""
    echo "$BODY"
  } > "$DEST/SKILL.md"

  ok "Конвертовано .mdc -> SKILL.md: $SKILL_NAME (⚠️ перевір вручну — автоконвертація best-effort)"
  INSTALLED_COUNT=$((INSTALLED_COUNT + 1))
done

if [ "$INSTALLED_COUNT" -eq 0 ]; then
  err "Жодного скіла не вдалося додати."
  exit 1
fi

# ---------- pack.json -------------------------------------------------------
PACK_JSON="$PACKS_DIR/$AUTHOR/$PACK_NAME/pack.json"
LICENSE_FILE=$(find "$SEARCH_ROOT" -maxdepth 1 -iname "LICENSE*" | head -1)
LICENSE_NOTE="unknown — перевір джерело"
[ -n "$LICENSE_FILE" ] && LICENSE_NOTE="see $(basename "$LICENSE_FILE") in source repo"

cat > "$PACK_JSON" <<EOF
{
  "pack_name": "$PACK_NAME",
  "author": "$AUTHOR",
  "source_url": "$URL",
  "ingested_at": "$(date -u +%Y-%m-%dT%H:%M:%SZ)",
  "skill_count": $INSTALLED_COUNT,
  "license_note": "$LICENSE_NOTE"
}
EOF

ok "pack.json створено: $PACK_JSON"
ok "Готово: $INSTALLED_COUNT скіл(ів) додано в packs/$AUTHOR/$PACK_NAME/"
info "Далі: ./scripts/build_registry.py щоб оновити registry.json"
