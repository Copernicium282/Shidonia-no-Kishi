#!/usr/bin/env bash
# Shidonia-no-Kishi plugin installer - the single entry point.
#
#   bash install.sh [--no-system] [--post-update]
#
# Or straight from the internet (no clone needed):
#   bash -c 'eval "$(curl -fsSL https://raw.githubusercontent.com/Copernicium282/Shidonia-no-Kishi/master/install.sh)"'
#
# What it does:
#   1. Stages this plugin persistently at ~/.local/share/shidonia-plugin
#      (survives upstream shell updates - the installer never touches it).
#   2. Runs plugin/apply.sh, which overlays the Shidonia customizations onto
#      the stock upstream install and chains future Settings-driven updates
#      back into the applier, so customizations survive updates.
#
# Requirements: a stock ilyamiro/serpantinum install. If you are coming from
# the old Shidonia fork build, run the upstream installer once first:
#   bash -c 'eval "$(curl -fsSL https://raw.githubusercontent.com/ilyamiro/serpantinum/master/install/install.sh)"'

set -euo pipefail

PLUGIN_REPO_URL="${PLUGIN_REPO_URL:-https://github.com/Copernicium282/Shidonia-no-Kishi.git}"
PLUGIN_HOME="$HOME/.local/share/shidonia-plugin"
SRC_CACHE="${XDG_CACHE_HOME:-$HOME/.cache}/shidonia-plugin-src"

SCRIPT_DIR=""
if [ -n "${BASH_SOURCE[0]:-}" ] && [ -f "${BASH_SOURCE[0]}" ]; then
    SCRIPT_DIR="$(dirname "$(realpath "${BASH_SOURCE[0]}")")"
fi

if [ -n "$SCRIPT_DIR" ] && [ -f "$SCRIPT_DIR/plugin/apply.sh" ]; then
    SRC_DIR="$SCRIPT_DIR"
else
    echo -e "\e[36m[ INFO ]\e[0m fetching plugin source..."
    command -v git >/dev/null 2>&1 || { echo -e "\e[31m[ FAIL ]\e[0m git required" >&2; exit 1; }
    if [ -d "$SRC_CACHE/.git" ]; then
        git -C "$SRC_CACHE" fetch --depth 1 origin master 2>/dev/null || true
        git -C "$SRC_CACHE" reset --hard origin/master 2>/dev/null || git -C "$SRC_CACHE" pull --ff-only 2>/dev/null || true
    else
        rm -rf "$SRC_CACHE"
        git clone --depth 1 "$PLUGIN_REPO_URL" "$SRC_CACHE"
    fi
    SRC_DIR="$SRC_CACHE"
fi

[ -f "$SRC_DIR/plugin/apply.sh" ] || { echo -e "\e[31m[ FAIL ]\e[0m plugin source incomplete ($SRC_DIR)" >&2; exit 1; }

mkdir -p "$PLUGIN_HOME"
cp -a "$SRC_DIR/plugin/." "$PLUGIN_HOME/plugin/"
chmod +x "$PLUGIN_HOME/plugin/apply.sh"

echo -e "\e[32m[  OK  ]\e[0m plugin staged at $PLUGIN_HOME"
exec bash "$PLUGIN_HOME/plugin/apply.sh" "$@"
