#!/bin/sh
#
# skills-vault universal installer for Mac/Linux
# curl -fsSL https://raw.githubusercontent.com/z0team/skills-vault/main/get.sh | sh
#

set -eu

REPO="z0team/skills-vault"
BRANCH="main"
RAW_URL="https://raw.githubusercontent.com/${REPO}/${BRANCH}"
TAR_URL="https://github.com/${REPO}/raw/${BRANCH}/dist/dist.tar.gz"

echo "🧰 skills-vault — Швидке встановлення скілів"
echo "==============================================="
echo ""

# Читаємо з /dev/tty щоб меню працювало у pipe
exec < /dev/tty || {
    echo "❌ Помилка: не вдалося відкрити /dev/tty для інтерактивного вводу."
    echo "Запустіть скрипт без pipe або реалізуйте headless режим."
    exit 1
}

echo "Куди ставимо скіли?"
echo "  1) Глобально (для всіх проєктів у системну папку)"
echo "  2) Локально (в поточну папку $(pwd))"
printf "Вибір [1-2]: "
read SCOPE_CHOICE

case "$SCOPE_CHOICE" in
  1) SCOPE="global" ;;
  2) SCOPE="local" ;;
  *) echo "❌ Невідомий вибір"; exit 1 ;;
esac

echo ""
echo "Для якого агента ставимо скіли?"
echo "  1) claude-code"
echo "  2) cursor"
echo "  3) copilot"
echo "  4) windsurf"
echo "  5) opencode"
echo "  6) codex"
echo "  7) agy"
echo "  8) Всі вище"
printf "Вибір (через кому, напр. 1,2 або 8): "
read AGENT_CHOICES

AGENTS=""
for c in $(echo "$AGENT_CHOICES" | tr ',' ' '); do
  case "$c" in
    1) AGENTS="$AGENTS claude-code" ;;
    2) AGENTS="$AGENTS cursor" ;;
    3) AGENTS="$AGENTS copilot" ;;
    4) AGENTS="$AGENTS windsurf" ;;
    5) AGENTS="$AGENTS opencode" ;;
    6) AGENTS="$AGENTS codex" ;;
    7) AGENTS="$AGENTS agy" ;;
    8) AGENTS="claude-code cursor copilot windsurf opencode codex agy" ;;
  esac
done

if [ -z "$AGENTS" ]; then
    echo "❌ Не обрано жодного агента."
    exit 1
fi

echo ""
echo "⏳ Завантаження registry.json..."
TMP_REGISTRY=$(mktemp)
curl -fsSL "$RAW_URL/registry.json" -o "$TMP_REGISTRY" || {
    echo "❌ Помилка завантаження registry.json"
    exit 1
}

# Parse basic packs info (we use grep to extract ids without jq dependency)
PACK_IDS=$(grep '"id":' "$TMP_REGISTRY" | sed 's/.*"id": "\(.*\)".*/\1/' | tr '\n' ' ')

echo ""
echo "Доступні паки:"
i=1
for pid in $PACK_IDS; do
    echo "  $i) $pid"
    i=$((i+1))
done
echo "  all) Всі паки"
printf "Які паки ставимо? (через кому, або 'all'): "
read PACK_CHOICES

SELECTED_PACKS=""
if [ "$PACK_CHOICES" = "all" ]; then
    SELECTED_PACKS="$PACK_IDS"
else
    for c in $(echo "$PACK_CHOICES" | tr ',' ' '); do
        i=1
        for pid in $PACK_IDS; do
            if [ "$i" = "$c" ]; then
                SELECTED_PACKS="$SELECTED_PACKS $pid"
            fi
            i=$((i+1))
        done
    done
fi

if [ -z "$SELECTED_PACKS" ]; then
    echo "❌ Не обрано жодного паку."
    exit 1
fi

echo ""
echo "⏳ Завантаження архіву скілів..."
TMP_DIR=$(mktemp -d)
trap 'rm -rf "$TMP_DIR" "$TMP_REGISTRY"' EXIT

curl -fsSL "$TAR_URL" | tar -xz -C "$TMP_DIR" || {
    echo "❌ Помилка розпакування. Можливо, dist.tar.gz відсутній."
    exit 1
}

HAS_MCP=0

for agent in $AGENTS; do
    # Resolve target directory
    DEST_DIR=""
    if [ "$SCOPE" = "global" ]; then
        if [ "$agent" = "cursor" ]; then
            echo "⚠️ Cursor не підтримує глобальні правила. Встановлюємо локально."
            DEST_DIR="$(pwd)"
        elif [ "$agent" = "claude-code" ]; then
            DEST_DIR="$HOME"
        else
            DEST_DIR="$HOME"
        fi
    else
        DEST_DIR="$(pwd)"
    fi
    
    mkdir -p "$DEST_DIR"
    
    echo "📦 Копіюємо для $agent у $DEST_DIR ..."
    for pid in $SELECTED_PACKS; do
        SRC_DIR="$TMP_DIR/$pid/$agent"
        if [ -d "$SRC_DIR" ]; then
            cp -R "$SRC_DIR/." "$DEST_DIR/" 2>/dev/null || cp -R "$SRC_DIR"/* "$DEST_DIR/"
        fi
        
        # Check MCP for this pack
        if grep -A 20 "\"id\": \"$pid\"" "$TMP_REGISTRY" | grep -q '"mcp_servers"'; then
            HAS_MCP=1
        fi
    done
done

echo ""
echo "✅ Успішно встановлено!"

if [ "$HAS_MCP" = "1" ]; then
    echo "⚠️ Увага: Деякі з встановлених паків потребують MCP сервер!"
    echo "   Перевірте документацію паку, щоб додати потрібну команду (наприклад, 'npx -y @21st-dev/cli@latest') до конфігурації вашого агента."
fi
