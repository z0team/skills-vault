#!/usr/bin/env bash
# install.sh — універсальний інсталятор скілів з skills-vault.
#
# Використання:
#   ./scripts/install.sh                         # інтерактивний режим
#   ./scripts/install.sh --skill <name> --agent claude-code --scope global
#   ./scripts/install.sh --pack <author/pack> --agent cursor --scope local --project /path/to/repo
#   ./scripts/install.sh --all --agent claude-code --scope global
#
# Опції:
#   --skill <name>        встановити один конкретний скіл (пошук по всіх паках)
#   --pack <author/pack>  встановити весь пак
#   --all                 встановити всі скіли з усіх паків
#   --agent <id>          claude-code | cursor | copilot | windsurf | agents-md | generic
#   --scope <s>           global | local
#   --project <path>      шлях до проєкту (обов'язково для --scope local)
#   --list                показати всі доступні скіли/паки і вийти
#
# Без аргументів — заходить в інтерактивний режим (питає все по черзі).

set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
PACKS_DIR="$ROOT_DIR/packs"
CONVERT="$ROOT_DIR/scripts/convert.py"

SKILL=""
PACK=""
ALL=0
AGENT=""
SCOPE=""
PROJECT=""
LIST=0

# ---------- helpers ----------------------------------------------------
err()  { echo "❌ $*" >&2; }
info() { echo "ℹ️  $*"; }
ok()   { echo "✅ $*"; }

usage() { sed -n '2,20p' "$0"; }

find_python() {
  command -v python3 >/dev/null 2>&1 && { echo python3; return; }
  command -v python  >/dev/null 2>&1 && { echo python; return; }
  err "Python3 не знайдено. Встанови python3 і спробуй знову."
  exit 1
}

ensure_pyyaml() {
  local py="$1"
  "$py" -c "import yaml" 2>/dev/null && return
  info "Встановлюю PyYAML (потрібен для конвертера)..."
  if ! "$py" -m pip install --quiet --break-system-packages pyyaml 2>/dev/null; then
    if ! "$py" -m pip install --quiet pyyaml 2>/dev/null; then
      err "Не вдалося автоматично встановити PyYAML. Встанови його вручну: $py -m pip install pyyaml"
      exit 1
    fi
  fi
}

all_skill_dirs() {
  # друкує: <author>|<pack>|<skill_name>|<abs_path_to_SKILL.md>
  find "$PACKS_DIR" -name "SKILL.md" -path "*/skills/*" 2>/dev/null | while read -r f; do
    local skill_dir pack_dir author_dir
    skill_dir="$(dirname "$f")"
    pack_dir="$(dirname "$(dirname "$skill_dir")")"
    author_dir="$(dirname "$pack_dir")"
    echo "$(basename "$author_dir")|$(basename "$pack_dir")|$(basename "$skill_dir")|$f"
  done
}

list_all() {
  echo "📦 Доступні паки та скіли:"
  echo ""
  local last_pack=""
  all_skill_dirs | sort | while IFS='|' read -r author pack skill path; do
    local key="$author/$pack"
    if [ "$key" != "$last_pack" ]; then
      echo "  $key"
      last_pack="$key"
    fi
    echo "    - $skill"
  done
}

# ---------- arg parsing --------------------------------------------------
while [ $# -gt 0 ]; do
  case "$1" in
    --skill) SKILL="$2"; shift 2 ;;
    --pack) PACK="$2"; shift 2 ;;
    --all) ALL=1; shift ;;
    --agent) AGENT="$2"; shift 2 ;;
    --scope) SCOPE="$2"; shift 2 ;;
    --project) PROJECT="$2"; shift 2 ;;
    --list) LIST=1; shift ;;
    -h|--help) usage; exit 0 ;;
    *) err "Невідома опція: $1"; usage; exit 1 ;;
  esac
done

if [ "$LIST" = "1" ]; then
  list_all
  exit 0
fi

PY="$(find_python)"
ensure_pyyaml "$PY"

# ---------- interactive mode ---------------------------------------------
if [ -z "$SKILL" ] && [ -z "$PACK" ] && [ "$ALL" = "0" ]; then
  echo "🧰 skills-vault — інтерактивна установка"
  echo ""
  list_all
  echo ""
  read -rp "Що встановлюємо? Введи 'author/pack' для всього паку, або 'author/pack/skill-name' для одного скіла, або 'all': " CHOICE
  if [ "$CHOICE" = "all" ]; then
    ALL=1
  else
    PARTS=$(echo "$CHOICE" | tr '/' ' ')
    set -- $PARTS
    if [ "$#" -eq 3 ]; then
      SKILL="$3"
      PACK="$1/$2"
    elif [ "$#" -eq 2 ]; then
      PACK="$1/$2"
    else
      err "Незрозумілий ввід: $CHOICE"
      exit 1
    fi
  fi
fi

if [ -z "$AGENT" ]; then
  echo ""
  echo "Для якого агента ставимо скіли?"
  echo "  1) claude-code"
  echo "  2) cursor"
  echo "  3) copilot"
  echo "  4) windsurf"
  echo "  5) opencode"
  echo "  6) codex"
  echo "  7) agy"
  echo "  8) agents-md (універсально)"
  echo "  9) generic (сирий SKILL.md)"
  read -rp "Вибір [1-9]: " AGENT_CHOICE
  case "$AGENT_CHOICE" in
    1) AGENT="claude-code" ;;
    2) AGENT="cursor" ;;
    3) AGENT="copilot" ;;
    4) AGENT="windsurf" ;;
    5) AGENT="opencode" ;;
    6) AGENT="codex" ;;
    7) AGENT="agy" ;;
    8) AGENT="agents-md" ;;
    9) AGENT="generic" ;;
    *) err "Невідомий вибір"; exit 1 ;;
  esac
fi

if [ -z "$SCOPE" ]; then
  echo ""
  echo "Куди ставимо?"
  echo "  1) global  — доступно у всіх проєктах"
  echo "  2) local   — тільки в конкретному проєкті"
  read -rp "Вибір [1-2]: " SCOPE_CHOICE
  case "$SCOPE_CHOICE" in
    1) SCOPE="global" ;;
    2) SCOPE="local" ;;
    *) err "Невідомий вибір"; exit 1 ;;
  esac
fi

if [ "$SCOPE" = "local" ] && [ -z "$PROJECT" ]; then
  read -rp "Шлях до проєкту: " PROJECT
fi

# ---------- resolve output dir per agent/scope ----------------------------
resolve_out_dir() {
  local agent="$1" scope="$2" project="$3"
  case "$agent" in
    claude-code)
      if [ "$scope" = "global" ]; then echo "$HOME/.claude"
      else echo "$project/.claude"; fi ;;
    cursor)
      if [ "$scope" = "global" ]; then
        err "Cursor не підтримує global rules у стабільній версії — встановлюю в local."
        echo "$project"
      else echo "$project"; fi ;;
    copilot|windsurf|opencode|codex|agy|agents-md|generic)
      if [ "$scope" = "global" ]; then echo "$HOME/.claude"
      else echo "$project"; fi ;;
    *) err "Невідомий агент: $agent"; exit 1 ;;
  esac
}

if [ "$SCOPE" = "local" ]; then
  [ -z "$PROJECT" ] && { err "Для local scope потрібен --project"; exit 1; }
  mkdir -p "$PROJECT"
  PROJECT="$(cd "$PROJECT" && pwd)"
fi

OUT_DIR="$(resolve_out_dir "$AGENT" "$SCOPE" "${PROJECT:-}")"
mkdir -p "$OUT_DIR"

# ---------- collect target SKILL.md files ----------------------------------
TARGETS_FILE="$(mktemp)"
trap 'rm -f "$TARGETS_FILE"' EXIT

if [ "$ALL" = "1" ]; then
  all_skill_dirs | cut -d'|' -f4 > "$TARGETS_FILE"
elif [ -n "$SKILL" ] && [ -n "$PACK" ]; then
  all_skill_dirs | awk -F'|' -v p="$PACK" -v s="$SKILL" '($1"/"$2)==p && $3==s {print $4}' > "$TARGETS_FILE"
elif [ -n "$PACK" ]; then
  all_skill_dirs | awk -F'|' -v p="$PACK" '($1"/"$2)==p {print $4}' > "$TARGETS_FILE"
elif [ -n "$SKILL" ]; then
  all_skill_dirs | awk -F'|' -v s="$SKILL" '$3==s {print $4}' > "$TARGETS_FILE"
fi

COUNT=$(wc -l < "$TARGETS_FILE" | tr -d ' ')
if [ "$COUNT" = "0" ]; then
  err "Нічого не знайдено за заданими критеріями (skill='$SKILL' pack='$PACK')."
  exit 1
fi

info "Встановлюю $COUNT скіл(ів) -> агент=$AGENT, scope=$SCOPE, dir=$OUT_DIR"
echo ""

while read -r skill_md; do
  "$PY" "$CONVERT" "$skill_md" --target "$AGENT" --out "$OUT_DIR" || err "Помилка конвертації: $skill_md (пропускаю)"
done < "$TARGETS_FILE"

echo ""
ok "Готово. Встановлено в: $OUT_DIR"
case "$AGENT" in
  claude-code) info "Перезапусти Claude Code сесію (або /skills reload), щоб підхопити нові скіли." ;;
  cursor) info "Cursor підхопить .cursor/rules автоматично у новому чаті." ;;
esac
