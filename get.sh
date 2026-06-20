#!/bin/sh
#
# skills-vault — Universal installer for Mac/Linux
# Usage: curl -fsSL https://raw.githubusercontent.com/z0team/skills-vault/main/get.sh | sh
#

set -eu

REPO="z0team/skills-vault"
BRANCH="main"
RAW_URL="https://raw.githubusercontent.com/${REPO}/${BRANCH}"
TAR_URL="https://github.com/${REPO}/raw/${BRANCH}/dist/dist.tar.gz"

# ─── Banner ───────────────────────────────────────────────────────────────────
printf '\033[36m'
cat << 'BANNER'
███████╗██╗  ██╗██╗██╗     ██╗     ███████╗
██╔════╝██║ ██╔╝██║██║     ██║     ██╔════╝
███████╗█████╔╝ ██║██║     ██║     ███████╗
╚════██║██╔═██╗ ██║██║     ██║     ╚════██║
███████║██║  ██╗██║███████╗███████╗███████║
╚══════╝╚═╝  ╚═╝╚═╝╚══════╝╚══════╝╚══════╝
BANNER
printf '\033[0m'
echo "  Universal AI Agent Skills Installer"
echo "  https://github.com/${REPO}"
echo ""

# ─── Interactive stdin ────────────────────────────────────────────────────────
exec < /dev/tty 2>/dev/null || {
    echo "✗ Cannot open /dev/tty for interactive input."
    echo "  Run the script directly (not piped): bash get.sh"
    exit 1
}

# ─── Helper ───────────────────────────────────────────────────────────────────
ask() {
    printf "\033[1m$1\033[0m "
}

divider() {
    echo "────────────────────────────────────────"
}

# ─── 1. Scope ─────────────────────────────────────────────────────────────────
divider
echo " 📂  Where would you like to install?"
echo "      1) Local  — current directory ($(pwd))"
echo "      2) Global — home directory (~)"
ask " →"; read SCOPE_CHOICE
case "$SCOPE_CHOICE" in
    1) SCOPE="local"  ;;
    2) SCOPE="global" ;;
    *) echo "✗ Invalid choice."; exit 1 ;;
esac

# ─── 2. Agents ────────────────────────────────────────────────────────────────
divider
echo " 🤖  Which AI agents are you using?"
echo "      1) Claude Code"
echo "      2) Cursor"
echo "      3) GitHub Copilot"
echo "      4) Windsurf"
echo "      5) OpenCode"
echo "      6) Codex"
echo "      7) Agy"
echo "      8) Roo / Cline"
echo "      9) Continue.dev"
echo "      0) ALL of the above"
ask " →  (comma-separated, e.g. 1,2 or 0):"; read AGENT_CHOICES

AGENTS=""
for c in $(echo "$AGENT_CHOICES" | tr ',' ' '); do
    case "$c" in
        1) AGENTS="$AGENTS claude-code" ;;
        2) AGENTS="$AGENTS cursor"      ;;
        3) AGENTS="$AGENTS copilot"     ;;
        4) AGENTS="$AGENTS windsurf"    ;;
        5) AGENTS="$AGENTS opencode"    ;;
        6) AGENTS="$AGENTS codex"       ;;
        7) AGENTS="$AGENTS agy"         ;;
        8) AGENTS="$AGENTS roo"         ;;
        9) AGENTS="$AGENTS continue"    ;;
        0) AGENTS="claude-code cursor copilot windsurf opencode codex agy roo continue" ;;
    esac
done

if [ -z "$AGENTS" ]; then
    echo "✗ No agent selected."; exit 1
fi

# ─── 3. Fetch registry ────────────────────────────────────────────────────────
divider
printf "  Fetching pack list... "
TMP_REGISTRY=$(mktemp)
curl -fsSL "$RAW_URL/registry.json" -o "$TMP_REGISTRY" 2>/dev/null || {
    echo ""
    echo "✗ Failed to fetch registry. Check your internet connection."
    exit 1
}
echo "done"

PACK_IDS=$(grep '"id":' "$TMP_REGISTRY" | sed 's/.*"id": "\(.*\)".*/\1/' | tr '\n' ' ')

# ─── 4. Select packs ──────────────────────────────────────────────────────────
divider
echo " 📦  Available skill packs:"
echo ""
i=1
for pid in $PACK_IDS; do
    printf "      %2d) %s\n" "$i" "$pid"
    i=$((i+1))
done
echo ""
echo "       a) ALL packs"
echo ""
ask " →  Select packs (comma-separated numbers or 'a'):"; read PACK_CHOICES

SELECTED_PACKS=""
if [ "$PACK_CHOICES" = "a" ] || [ "$PACK_CHOICES" = "all" ]; then
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
    echo "✗ No pack selected."; exit 1
fi

# ─── 5. Download & install ────────────────────────────────────────────────────
divider
printf "  Downloading skills archive... "
TMP_DIR=$(mktemp -d)
trap 'rm -rf "$TMP_DIR" "$TMP_REGISTRY"' EXIT

curl -fsSL "$TAR_URL" | tar -xz -C "$TMP_DIR" 2>/dev/null || {
    echo ""
    echo "✗ Download failed. dist.tar.gz may be missing — try running the build first."
    exit 1
}
echo "done"
echo ""

HAS_MCP=0
INSTALLED=0

for agent in $AGENTS; do
    if [ "$SCOPE" = "global" ]; then
        if [ "$agent" = "cursor" ]; then
            printf "  \033[33m⚠\033[0m  Cursor doesn't support global rules — installing locally.\n"
            DEST_DIR="$(pwd)"
        else
            DEST_DIR="$HOME"
        fi
    else
        DEST_DIR="$(pwd)"
    fi

    mkdir -p "$DEST_DIR"

    for pid in $SELECTED_PACKS; do
        SRC_DIR="$TMP_DIR/$pid/$agent"
        if [ -d "$SRC_DIR" ]; then
            cp -R "$SRC_DIR/." "$DEST_DIR/" 2>/dev/null || true
            printf "  \033[32m✓\033[0m  %-35s → %s [%s]\n" "$pid" "$DEST_DIR" "$agent"
            INSTALLED=$((INSTALLED+1))
        fi

        if grep -A 20 "\"id\": \"$pid\"" "$TMP_REGISTRY" 2>/dev/null | grep -q '"mcp_servers"'; then
            HAS_MCP=1
        fi
    done
done

# ─── Done ─────────────────────────────────────────────────────────────────────
divider
printf "\033[32m✓  Done! %d pack(s) installed.\033[0m\n" "$INSTALLED"

if [ "$HAS_MCP" = "1" ]; then
    echo ""
    printf "\033[33m⚠  Some packs require an MCP server.\033[0m\n"
    echo "   Check each pack's docs to configure the required MCP command"
    echo "   (e.g. npx -y @21st-dev/cli@latest) in your agent settings."
fi
echo ""
