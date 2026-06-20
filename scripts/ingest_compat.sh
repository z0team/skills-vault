#!/usr/bin/env bash
# ingest_compat.sh — bash 3.2-compatible version of ingest.sh
# Handles: github.com/owner/repo, /tree/branch/subpath, /blob/branch/file
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
PACKS_DIR="$ROOT_DIR/packs"

URL=""
NAME_OVERRIDE=""
AUTHOR_OVERRIDE=""

err()  { echo "❌ $*" >&2; }
info() { echo "ℹ️  $*"; }
ok()   { echo "✅ $*"; }

while [ $# -gt 0 ]; do
  case "$1" in
    --name)   NAME_OVERRIDE="$2"; shift 2 ;;
    --author) AUTHOR_OVERRIDE="$2"; shift 2 ;;
    -h|--help) sed -n '2,5p' "$0"; exit 0 ;;
    *)
      if [ -z "$URL" ]; then URL="$1"; shift
      else err "Unknown option: $1"; exit 1; fi ;;
  esac
done

[ -z "$URL" ] && { err "Need a URL. Example: ./scripts/ingest_compat.sh https://github.com/owner/repo"; exit 1; }

# ---------- parse URL -------------------------------------------------------
CLEAN_URL="${URL%/}"
GH_OWNER="" GH_REPO="" GH_SUBPATH="" IS_BLOB=0

# blob URL: /blob/branch/path/to/SKILL.md
if echo "$CLEAN_URL" | grep -qE 'github\.com/[^/]+/[^/]+/blob/'; then
  GH_OWNER=$(echo "$CLEAN_URL" | sed -E 's|https://github.com/([^/]+)/.*|\1|')
  GH_REPO=$(echo "$CLEAN_URL"  | sed -E 's|https://github.com/[^/]+/([^/]+)/.*|\1|')
  # strip /blob/<branch>/ to get subpath
  GH_SUBPATH=$(echo "$CLEAN_URL" | sed -E 's|https://github.com/[^/]+/[^/]+/blob/[^/]+/||')
  IS_BLOB=1
# tree URL: /tree/branch/path
elif echo "$CLEAN_URL" | grep -qE 'github\.com/[^/]+/[^/]+/tree/'; then
  GH_OWNER=$(echo "$CLEAN_URL" | sed -E 's|https://github.com/([^/]+)/.*|\1|')
  GH_REPO=$(echo "$CLEAN_URL"  | sed -E 's|https://github.com/[^/]+/([^/]+)/.*|\1|')
  GH_SUBPATH=$(echo "$CLEAN_URL" | sed -E 's|https://github.com/[^/]+/[^/]+/tree/[^/]+/||')
# plain repo URL
elif echo "$CLEAN_URL" | grep -qE 'github\.com/[^/]+/[^/]+$'; then
  GH_OWNER=$(echo "$CLEAN_URL" | sed -E 's|https://github.com/([^/]+)/.*|\1|')
  GH_REPO=$(echo "$CLEAN_URL"  | sed -E 's|https://github.com/[^/]+/([^/]+)$|\1|')
  GH_SUBPATH=""
else
  err "Only github.com URLs supported. Got: $URL"
  exit 1
fi

GH_REPO="${GH_REPO%.git}"
AUTHOR="${AUTHOR_OVERRIDE:-$GH_OWNER}"
PACK_NAME="${NAME_OVERRIDE:-$GH_REPO}"

# Normalize pack name to kebab-case lowercase
PACK_NAME=$(echo "$PACK_NAME" | tr '[:upper:]' '[:lower:]' | sed 's/[^a-z0-9]/-/g' | sed 's/--*/-/g' | sed 's/^-//;s/-$//')

REPO_CLONE_URL="https://github.com/$GH_OWNER/$GH_REPO.git"
TMP_DIR="$(mktemp -d)"
trap 'rm -rf "$TMP_DIR"' EXIT

info "Cloning $REPO_CLONE_URL ..."
if ! git clone --depth 1 --quiet "$REPO_CLONE_URL" "$TMP_DIR/repo" 2>&1; then
  err "Failed to clone. Check URL and network access."
  exit 1
fi

# ---------- determine search root ------------------------------------------
SEARCH_ROOT="$TMP_DIR/repo"
if [ -n "$GH_SUBPATH" ]; then
  if [ "$IS_BLOB" = "1" ]; then
    # blob points to a file — use its parent directory
    SEARCH_ROOT="$TMP_DIR/repo/$(dirname "$GH_SUBPATH")"
  else
    SEARCH_ROOT="$TMP_DIR/repo/$GH_SUBPATH"
  fi
fi

if [ ! -d "$SEARCH_ROOT" ]; then
  err "Subpath not found in repo: $GH_SUBPATH"
  exit 1
fi

# ---------- find SKILL.md files (bash 3.2 compatible) ----------------------
SKILL_FILES_TMP="$(mktemp)"
find "$SEARCH_ROOT" -name "SKILL.md" -not -path "*/node_modules/*" -not -path "*/.git/*" 2>/dev/null > "$SKILL_FILES_TMP"
SKILL_COUNT=$(wc -l < "$SKILL_FILES_TMP" | tr -d ' ')

MDC_FILES_TMP="$(mktemp)"
if [ "$SKILL_COUNT" -eq 0 ]; then
  info "No SKILL.md found. Looking for .mdc / .cursor/rules for conversion..."
  find "$SEARCH_ROOT" -name "*.mdc" -not -path "*/node_modules/*" -not -path "*/.git/*" 2>/dev/null > "$MDC_FILES_TMP"
  MDC_COUNT=$(wc -l < "$MDC_FILES_TMP" | tr -d ' ')
  if [ "$MDC_COUNT" -eq 0 ]; then
    # Last resort: look for README.md as skill description
    info "No .mdc either. Will try README.md as SKILL.md source..."
    MDC_COUNT=0
  fi
fi

DEST_SKILLS_DIR="$PACKS_DIR/$AUTHOR/$PACK_NAME/skills"
mkdir -p "$DEST_SKILLS_DIR"
INSTALLED_COUNT=0

# ---------- copy canonical SKILL.md files ----------------------------------
if [ "$SKILL_COUNT" -gt 0 ]; then
  while IFS= read -r f; do
    [ -z "$f" ] && continue
    SKILL_DIR="$(dirname "$f")"
    SKILL_NAME="$(basename "$SKILL_DIR")"

    # Try to get name from frontmatter
    FM_NAME=$(grep -m1 '^name:' "$f" 2>/dev/null | sed -E 's/^name:[[:space:]]*//' | sed -E 's/^"//;s/"$//' | tr -d "'" || true)
    if [ -n "$FM_NAME" ]; then
      # normalize to kebab-case
      SKILL_NAME=$(echo "$FM_NAME" | tr '[:upper:]' '[:lower:]' | sed 's/[^a-z0-9]/-/g' | sed 's/--*/-/g' | sed 's/^-//;s/-$//')
    fi

    # Skip if skill dir name is the pack root itself (single-skill repos)
    DEST="$DEST_SKILLS_DIR/$SKILL_NAME"
    mkdir -p "$DEST"

    # Copy skill dir contents, excluding junk
    rsync -a --exclude='.git' --exclude='node_modules' --exclude='.github' \
      "$SKILL_DIR/" "$DEST/" 2>/dev/null \
      || cp -r "$SKILL_DIR/." "$DEST/"

    ok "Added skill: $SKILL_NAME"
    INSTALLED_COUNT=$((INSTALLED_COUNT + 1))
  done < "$SKILL_FILES_TMP"
fi

# ---------- convert .mdc -> SKILL.md ---------------------------------------
if [ "$SKILL_COUNT" -eq 0 ] && [ -s "$MDC_FILES_TMP" ]; then
  while IFS= read -r f; do
    [ -z "$f" ] && continue
    SKILL_NAME="$(basename "$f" .mdc)"
    SKILL_NAME=$(echo "$SKILL_NAME" | tr '[:upper:]' '[:lower:]' | sed 's/[^a-z0-9]/-/g' | sed 's/--*/-/g' | sed 's/^-//;s/-$//')
    DEST="$DEST_SKILLS_DIR/$SKILL_NAME"
    mkdir -p "$DEST"

    DESC=$(awk '/^description:/{sub(/^description:[[:space:]]*/,""); print; exit}' "$f" | sed -E 's/^"//;s/"$//')
    [ -z "$DESC" ] && DESC="(description missing from source — fill in manually)"

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

    # Copy any supporting files from the same dir
    cp "$f" "$DEST/ORIGINAL.mdc" 2>/dev/null || true

    ok "Converted .mdc -> SKILL.md: $SKILL_NAME (⚠️ review manually)"
    INSTALLED_COUNT=$((INSTALLED_COUNT + 1))
  done < "$MDC_FILES_TMP"
fi

# ---------- fallback: README.md as SKILL.md --------------------------------
if [ "$INSTALLED_COUNT" -eq 0 ]; then
  README="$SEARCH_ROOT/README.md"
  if [ -f "$README" ]; then
    SKILL_NAME="$PACK_NAME"
    DEST="$DEST_SKILLS_DIR/$SKILL_NAME"
    mkdir -p "$DEST"

    # Extract first non-empty line after # heading as description
    DESC=$(awk 'NR>1 && /^[^#]/ && length($0)>10 {print; exit}' "$README" | head -c 200 | tr '"' "'")
    [ -z "$DESC" ] && DESC="See README for details."

    # Copy everything from search root (minus junk)
    rsync -a --exclude='.git' --exclude='node_modules' --exclude='.github' \
      "$SEARCH_ROOT/" "$DEST/" 2>/dev/null \
      || cp -r "$SEARCH_ROOT/." "$DEST/"

    # Rename README.md -> ORIGINAL_README.md, create SKILL.md
    if [ -f "$DEST/README.md" ]; then
      cp "$DEST/README.md" "$DEST/ORIGINAL_README.md"
    fi

    {
      echo "---"
      echo "name: $SKILL_NAME"
      echo "description: \"$DESC\""
      echo "source: \"$URL\""
      echo "---"
      echo ""
      cat "$README"
    } > "$DEST/SKILL.md"

    ok "Created SKILL.md from README.md: $SKILL_NAME (⚠️ review manually)"
    INSTALLED_COUNT=$((INSTALLED_COUNT + 1))
  else
    err "No SKILL.md, .mdc, or README.md found in $URL"
    rm -f "$SKILL_FILES_TMP" "$MDC_FILES_TMP"
    exit 1
  fi
fi

rm -f "$SKILL_FILES_TMP" "$MDC_FILES_TMP"

# ---------- strip junk from all installed skills ---------------------------
find "$DEST_SKILLS_DIR" -name ".git" -type d -exec rm -rf {} + 2>/dev/null || true
find "$DEST_SKILLS_DIR" -name "node_modules" -type d -exec rm -rf {} + 2>/dev/null || true
find "$DEST_SKILLS_DIR" -name ".github" -type d -exec rm -rf {} + 2>/dev/null || true

# ---------- pack.json -------------------------------------------------------
PACK_JSON="$PACKS_DIR/$AUTHOR/$PACK_NAME/pack.json"
LICENSE_FILE=$(find "$SEARCH_ROOT" -maxdepth 2 -iname "LICENSE*" 2>/dev/null | head -1)
LICENSE_NOTE="unknown — check source"
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

ok "pack.json created: $PACK_JSON"
ok "Done: $INSTALLED_COUNT skill(s) added to packs/$AUTHOR/$PACK_NAME/"
info "Next: ./scripts/build_registry.py to update registry.json"
