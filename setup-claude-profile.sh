#!/usr/bin/env bash
# setup-claude-profile.sh — create an isolated Claude Code profile pointed at OmniRoute.
# Never touches your real ~/.claude.

set -euo pipefail

PROFILE_DIR="${CLAUDE_OMNIROUTE_PROFILE:-$HOME/.claude-omniroute-test}"
BASE_URL="${OMNIROUTE_BASE_URL:-http://localhost:20128}"
MODEL="${OMNIROUTE_MODEL:-auto/coding}"
KEY="${OMNIROUTE_API_KEY:-}"

if [ -z "$KEY" ]; then
  echo "ERROR: set OMNIROUTE_API_KEY first."
  echo "  export OMNIROUTE_API_KEY='sk-...'   # from $BASE_URL/dashboard"
  exit 1
fi

# Gotcha 2: a trailing /v1 breaks Claude Code — it appends the path itself.
case "$BASE_URL" in
  */v1|*/v1/)
    BASE_URL="${BASE_URL%/}"; BASE_URL="${BASE_URL%/v1}"
    echo "NOTE: stripped trailing /v1 -> $BASE_URL"
    ;;
esac

mkdir -p "$PROFILE_DIR"
SETTINGS="$PROFILE_DIR/settings.json"

if [ -e "$SETTINGS" ]; then
  cp "$SETTINGS" "$SETTINGS.bak.$(date +%s)"
  echo "Backed up existing settings.json"
fi

# Gotcha 1: must be an "env" block. Gotcha 3: map all three model tiers.
cat > "$SETTINGS" <<EOF
{
  "env": {
    "ANTHROPIC_BASE_URL": "$BASE_URL",
    "ANTHROPIC_AUTH_TOKEN": "$KEY",
    "ANTHROPIC_DEFAULT_OPUS_MODEL": "$MODEL",
    "ANTHROPIC_DEFAULT_SONNET_MODEL": "$MODEL",
    "ANTHROPIC_DEFAULT_HAIKU_MODEL": "$MODEL"
  }
}
EOF

chmod 600 "$SETTINGS"

echo "Wrote $SETTINGS (mode 600)"
echo ""
echo "Work in a scratch directory so the agent can't touch system paths:"
echo "  mkdir -p ~/omniroute-scratch && cd ~/omniroute-scratch"
echo ""
echo "Then launch:"
echo "  CLAUDE_CONFIG_DIR=\"$PROFILE_DIR\" claude"
