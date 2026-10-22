#!/usr/bin/env bash
# Shidonia-no-Kishi plugin applier.
#
# Idempotent: re-applying over an already-customized install is a no-op,
# EXCEPT it always re-chains the Settings Update command (stock updates wipe
# that hook) and re-asserts the SDDM login theme (stock updates reset it).
#
# Usage:
#   apply.sh [--post-update] [--no-system] [--if-changed]
#            [--share-dir DIR] [--config FILE] [--plugin-dir DIR]
#
#   --post-update  same as a normal run; marks the invocation as coming from
#                  the Settings Update chain (log line only).
#   --no-system    skip sudo/system steps (SDDM, GRUB, packages). Useful for
#                  testing or single-user containers.
#   --if-changed   exit early unless the installed shell version differs from
#                  the last applied version. Implies --no-system; used by the
#                  login-time autoheal unit.
#   --grub         install/refresh the GRUB theme (default: auto-detect).
#   --no-grub      never touch GRUB; for Limine, systemd-boot, or other
#                  bootloaders. The choice is remembered for future updates.
#
# Env overrides (mainly for testing):
#   SERPANTINUM_SHARE   installed shell dir (default ~/.local/share/serpantinum)
#   SERPANTINUM_CONFIG  user settings.json (default ~/.config/serpantinum/settings.json)

set -euo pipefail

POST_UPDATE=false
NO_SYSTEM=false
IF_CHANGED=false
GRUB_MODE="auto"
SHARE_DIR="${SERPANTINUM_SHARE:-$HOME/.local/share/serpantinum}"
CONFIG_FILE="${SERPANTINUM_CONFIG:-$HOME/.config/serpantinum/settings.json}"
PLUGIN_DIR=""

while [[ "$#" -gt 0 ]]; do
    case "$1" in
        --post-update) POST_UPDATE=true; shift ;;
        --no-system) NO_SYSTEM=true; shift ;;
        --if-changed) IF_CHANGED=true; NO_SYSTEM=true; shift ;;
        --grub) GRUB_MODE=true; shift ;;
        --no-grub) GRUB_MODE=false; shift ;;
        --share-dir) SHARE_DIR="$2"; shift 2 ;;
        --config) CONFIG_FILE="$2"; shift 2 ;;
        --plugin-dir) PLUGIN_DIR="$2"; shift 2 ;;
        *) echo "unknown arg: $1" >&2; exit 1 ;;
    esac
done

if [ -z "$PLUGIN_DIR" ]; then
    PLUGIN_DIR="$(dirname "$(realpath "${BASH_SOURCE[0]}")")"
fi
PATCHES_DIR="$PLUGIN_DIR/patches"
PAYLOAD_DIR="$PLUGIN_DIR/payload"
STATE_FILE="$PLUGIN_DIR/state.json"

# Remember a previous --grub/--no-grub choice so the Settings update chain
# keeps honoring it without having to repeat the flag.
if [ "$GRUB_MODE" = "auto" ] && [ -f "$STATE_FILE" ]; then
    STORED_GRUB=$(python3 -c '
import json, sys
try:
    v = json.load(open(sys.argv[1])).get("grub_theme")
    print("" if v is None else ("true" if v else "false"))
except Exception:
    print("")
' "$STATE_FILE" 2>/dev/null || true)
    case "$STORED_GRUB" in
        true|false) GRUB_MODE="$STORED_GRUB" ;;
    esac
fi

# Persistent-install location: the Settings Update chain calls this exact
# path, so warn if running from anywhere else.
CANONICAL_APPLY="$HOME/.local/share/shidonia-plugin/plugin/apply.sh"
if [ "$(realpath "$PLUGIN_DIR/apply.sh" 2>/dev/null || echo "$PLUGIN_DIR/apply.sh")" != "$(realpath "$CANONICAL_APPLY" 2>/dev/null || echo "$CANONICAL_APPLY")" ]; then
    echo -e "\e[33m[ WARN ]\e[0m running from $PLUGIN_DIR - run install.sh so the"
    echo -e "         plugin persists at ~/.local/share/shidonia-plugin for post-update hooks"
fi

if [ "$POST_UPDATE" = true ]; then
    echo -e "\e[36m[ INFO ]\e[0m post-update hook: re-applying Shidonia customizations"
fi

[ -d "$SHARE_DIR/src" ] || { echo -e "\e[31m[ FAIL ]\e[0m no serpantinum install at $SHARE_DIR" >&2; exit 1; }

STATE_VERSION_FILE="${QS_STATE_DIR:-${XDG_STATE_HOME:-$HOME/.local/state}/serpantinum}/version"
SHELL_VER=""
if [ -f "$STATE_VERSION_FILE" ]; then
    SHELL_VER=$(awk -F= '/^SERPANTINUM_VERSION=/{gsub(/"/, "", $2); print $2}' "$STATE_VERSION_FILE")
fi

if [ "$IF_CHANGED" = true ]; then
    APPLIED_VER=$(python3 -c '
import json, sys
try:
    print(json.load(open(sys.argv[1])).get("shell_version", ""))
except Exception:
    print("")
' "$STATE_FILE" 2>/dev/null || true)
    if [ -n "$SHELL_VER" ] && [ "$SHELL_VER" = "$APPLIED_VER" ]; then
        exit 0
    fi
    echo -e "\e[36m[ INFO ]\e[0m shell changed ${APPLIED_VER:-unknown} -> ${SHELL_VER:-unknown}, re-applying"
fi

source "$PLUGIN_DIR/system.sh"

if [ "$NO_SYSTEM" = false ]; then
    ensure_user_deps
    ensure_extra_pkgs
else
    for cmd in jq python3 patch; do
        command -v "$cmd" >/dev/null 2>&1 || { echo -e "\e[31m[ FAIL ]\e[0m missing '$cmd' (and --no-system skips auto-install)" >&2; exit 1; }
    done
fi

# 1. Theme preset file overlay (extra file - stock updates simply delete it).
THEME_SRC="$PAYLOAD_DIR/shell/src/assets/themes/Tsugumori.json"
THEME_DST="$SHARE_DIR/src/assets/themes/Tsugumori.json"
if [ -f "$THEME_SRC" ]; then
    if [ ! -f "$THEME_DST" ] || ! cmp -s "$THEME_SRC" "$THEME_DST"; then
        cp "$THEME_SRC" "$THEME_DST"
        echo -e "\e[32m[  OK  ]\e[0m Tsugumori theme installed"
    else
        echo -e "\e[32m[  OK  ]\e[0m Tsugumori theme already intact"
    fi
fi

# 2. QML tweaks, applied as patches so upstream refactors fail loudly
#    instead of silently reverting.
#
# Upstream 2.3.0 merged the side faces into <Name>Face.qml and made bar
# thickness + content scaling native. Detect the installed layout instead of
# comparing version numbers, so both architectures keep working.
PATCH_FAILED=0
PATCHES=()
if [ -f "$SHARE_DIR/src/quickshell/bar/faces/bat/SideBatFace.qml" ]; then
    echo -e "\e[36m[ INFO ]\e[0m legacy bar layout (2.2.x): applying side-face patches"
    PATCHES+=(
        "bar-thickness.patch"
        "side-weather-scale.patch"
        "side-timedate-scale.patch"
        "side-bat-square.patch"
    )
elif [ -f "$SHARE_DIR/src/quickshell/bar/faces/bat/BatFace.qml" ]; then
    echo -e "\e[36m[ INFO ]\e[0m unified bar layout (2.3+): thickness and content scaling are native"
    PATCHES+=("bat-square.patch")
else
    echo -e "\e[31m[ FAIL ]\e[0m unrecognized bar layout: no bat face found" >&2
    PATCH_FAILED=$((PATCH_FAILED + 1))
fi
PATCHES+=("matugen-config.patch" "matugen-config-static.patch")

for p in "${PATCHES[@]}"; do
    [ -f "$PATCHES_DIR/$p" ] || { echo -e "\e[33m[ SKIP ]\e[0m $p not shipped"; continue; }
    if patch -p1 --forward --dry-run --silent -d "$SHARE_DIR" < "$PATCHES_DIR/$p" >/dev/null 2>&1; then
        patch -p1 --forward -d "$SHARE_DIR" < "$PATCHES_DIR/$p" >/dev/null
        echo -e "\e[32m[  OK  ]\e[0m applied $p"
    elif patch -p1 --reverse --dry-run --silent -d "$SHARE_DIR" < "$PATCHES_DIR/$p" >/dev/null 2>&1; then
        echo -e "\e[32m[  OK  ]\e[0m $p already intact"
    else
        echo -e "\e[31m[ FAIL ]\e[0m $p does not apply - upstream changed these files." >&2
        echo -e "         Update the plugin patches, then re-run. Settings/system steps below still run." >&2
        PATCH_FAILED=$((PATCH_FAILED + 1))
    fi
done

# 3. User settings: managed defaults, user edits always win (see merge-settings.py).
if [ -f "$CONFIG_FILE" ] || [ ! -e "$CONFIG_FILE" ]; then
    mkdir -p "$(dirname "$CONFIG_FILE")"
    python3 "$PLUGIN_DIR/merge-settings.py" "$CONFIG_FILE" "$PLUGIN_DIR/settings-overlay.json" "$STATE_FILE"
fi

# 4. Chain the Settings Update button back into this applier.
CHAIN_FAILED=0
ABOUTTAB="$SHARE_DIR/src/quickshell/guide/AboutTab.qml"
if [ -f "$ABOUTTAB" ]; then
    if [ "$PLUGIN_DIR" = "$HOME/.local/share/shidonia-plugin/plugin" ]; then
        CHAIN_APPLY="$CANONICAL_APPLY"
    else
        CHAIN_APPLY="$PLUGIN_DIR/apply.sh"
    fi
    if ! python3 "$PLUGIN_DIR/patch-abouttab.py" "$ABOUTTAB" "$CHAIN_APPLY"; then
        echo -e "\e[31m[ FAIL ]\e[0m Settings Update chain was not installed" >&2
        CHAIN_FAILED=1
    fi
else
    echo -e "\e[31m[ FAIL ]\e[0m AboutTab.qml not found, update chain not installed" >&2
    CHAIN_FAILED=1
fi

# 5. System-level customizations (skipped with --no-system).
if [ "$NO_SYSTEM" = false ]; then
    setup_sddm_theme
    if [ "$GRUB_MODE" = "false" ]; then
        echo -e "\e[33m[ SKIP ]\e[0m GRUB theme (disabled for this install)"
    else
        setup_grub_theme
    fi
    setup_darkmode
    disable_telemetry
else
    echo -e "\e[33m[ SKIP ]\e[0m system steps (--no-system)"
fi

# 6. Record application.
python3 - "$STATE_FILE" "$SHELL_VER" "$GRUB_MODE" <<'EOF'
import json, sys, time
path, ver, grub = sys.argv[1:4]
try:
    with open(path) as f: state = json.load(f)
except (FileNotFoundError, json.JSONDecodeError):
    state = {}
state["applied_at"] = int(time.time())
state["shell_version"] = ver
if grub != "auto":
    state["grub_theme"] = (grub == "true")
with open(path, "w") as f:
    json.dump(state, f, indent=2)
    f.write("\n")
EOF

if [ "$PATCH_FAILED" -gt 0 ] || [ "$CHAIN_FAILED" -gt 0 ]; then
    echo -e "\e[31m[ FAIL ]\e[0m Shidonia customizations incomplete (failed patches: $PATCH_FAILED, update chain failed: $CHAIN_FAILED)" >&2
    exit 1
fi

echo -e "\e[32m[ DONE ]\e[0m Shidonia customizations in place (shell ${SHELL_VER:-unknown})"
