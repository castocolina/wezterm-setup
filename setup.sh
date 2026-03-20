#!/bin/bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
WEZTERM_DEST="$HOME/.config/wezterm"
BIN_DEST="$HOME/.local/bin"
SOURCE_LINE='[[ -f ~/.local/bin/wez-tab ]] && source ~/.local/bin/wez-tab 2>/dev/null || true'

# Detect shell rc file
detect_rc() {
  case "$(basename "${SHELL:-/bin/bash}")" in
    zsh)  echo "$HOME/.zshrc" ;;
    *)    echo "$HOME/.bashrc" ;;
  esac
}

usage() {
  cat <<'EOF'
Usage: setup.sh [--uninstall] [--help]

  (no args)     Install wezterm config and wez-tab
  --uninstall   Remove installed files and shell integration
  --help        Show this message
EOF
}

install() {
  local rc
  rc="$(detect_rc)"

  echo "Installing wezterm-setup..."

  # Copy wezterm config
  mkdir -p "$WEZTERM_DEST"
  cp "$SCRIPT_DIR/config/wezterm.lua" "$WEZTERM_DEST/wezterm.lua"
  echo "  ✓ config → $WEZTERM_DEST/wezterm.lua"

  # Copy wez-tab binary
  mkdir -p "$BIN_DEST"
  cp "$SCRIPT_DIR/bin/wez-tab" "$BIN_DEST/wez-tab"
  chmod +x "$BIN_DEST/wez-tab"
  echo "  ✓ bin    → $BIN_DEST/wez-tab"

  # Add source line to shell rc if not present
  if [ -f "$rc" ] && grep -qF "source ~/.local/bin/wez-tab" "$rc"; then
    echo "  ✓ shell  → already configured in $rc"
  else
    echo "" >> "$rc"
    echo "# WezTerm tab color/autocomplete support" >> "$rc"
    echo "$SOURCE_LINE" >> "$rc"
    echo "  ✓ shell  → added source line to $rc"
  fi

  # Ensure ~/.local/bin is in PATH
  if [ -f "$rc" ] && grep -qF 'PATH.*\.local/bin' "$rc"; then
    echo "  ✓ PATH   → ~/.local/bin already in $rc"
  else
    echo 'export PATH="$HOME/.local/bin:$PATH"' >> "$rc"
    echo "  ✓ PATH   → added ~/.local/bin to $rc"
  fi

  echo ""
  echo "Done! Restart your shell or run: source $rc"
}

uninstall() {
  local rc
  rc="$(detect_rc)"

  echo "Uninstalling wezterm-setup..."

  # Remove files
  if [ -f "$WEZTERM_DEST/wezterm.lua" ]; then
    rm "$WEZTERM_DEST/wezterm.lua"
    echo "  ✓ removed $WEZTERM_DEST/wezterm.lua"
  fi

  if [ -f "$BIN_DEST/wez-tab" ]; then
    rm "$BIN_DEST/wez-tab"
    echo "  ✓ removed $BIN_DEST/wez-tab"
  fi

  # Remove source line from rc
  if [ -f "$rc" ]; then
    sed -i '/# WezTerm tab color\/autocomplete support/d' "$rc"
    sed -i '/source ~\/\.local\/bin\/wez-tab/d' "$rc"
    echo "  ✓ removed wez-tab lines from $rc"
  fi

  echo ""
  echo "Done!"
}

case "${1:-}" in
  --uninstall) uninstall ;;
  --help|-h)   usage ;;
  "")          install ;;
  *)
    echo "Error: unknown option '$1'" >&2
    usage >&2
    exit 1
    ;;
esac
