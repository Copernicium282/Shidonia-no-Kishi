#!/usr/bin/env bash
# Shidonia-no-Kishi plugin: privileged/system customization steps.
# All functions are idempotent. Sourced by plugin/apply.sh, not run directly.

PLUGIN_PAYLOAD="$PLUGIN_DIR/payload"

need_cmd() {
    if ! command -v "$1" >/dev/null 2>&1; then
        echo -e "\e[31m[ FAIL ]\e[0m required command '$1' not found" >&2
        return 1
    fi
}

ensure_user_deps() {
    local missing=()
    for cmd in jq python3 patch; do
        command -v "$cmd" >/dev/null 2>&1 || missing+=("$cmd")
    done
    if [ "${#missing[@]}" -eq 0 ]; then
        return 0
    fi
    if ! command -v pacman >/dev/null 2>&1; then
        echo -e "\e[31m[ FAIL ]\e[0m missing ${missing[*]} and no pacman to install them" >&2
        return 1
    fi
    local pkgs=()
    for cmd in "${missing[@]}"; do
        case "$cmd" in
            jq) pkgs+=("jq") ;;
            python3) pkgs+=("python") ;;
            patch) pkgs+=("patch") ;;
        esac
    done
    sudo pacman -S --noconfirm --needed "${pkgs[@]}"
}

ensure_extra_pkgs() {
    command -v pacman >/dev/null 2>&1 || return 0
    sudo pacman -S --noconfirm --needed gsettings-desktop-schemas 2>/dev/null || true
    if command -v yay >/dev/null 2>&1; then
        yay -S --noconfirm --needed overskride-bin 2>/dev/null || true
    elif command -v paru >/dev/null 2>&1; then
        paru -S --noconfirm --needed overskride-bin 2>/dev/null || true
    else
        echo -e "\e[33m[ SKIP ]\e[0m no AUR helper (yay/paru); skipping overskride-bin"
    fi
}

setup_sddm_theme() {
    local theme_src="$PLUGIN_PAYLOAD/sddm/sidonia-no-kishi"
    local theme_dest="/usr/share/sddm/themes/sidonia-no-kishi"
    local conf="/etc/sddm.conf.d/10-sidonia-no-kishi.conf"

    [ -d "$theme_src" ] || { echo -e "\e[33m[ SKIP ]\e[0m SDDM payload missing"; return 0; }
    command -v sddm >/dev/null 2>&1 || { echo -e "\e[33m[ SKIP ]\e[0m sddm not installed"; return 0; }

    sudo mkdir -p "$theme_dest"
    sudo cp -r "$theme_src/." "$theme_dest/"
    sudo mkdir -p /etc/sddm.conf.d
    cat <<EOF | sudo tee "$conf" > /dev/null
[Theme]
Current=sidonia-no-kishi
ThemeDir=/usr/share/sddm/themes

[General]
GreeterEnvironment=QT_WAYLAND_DISABLE_WINDOWDECORATION=1
InputMethod=
EOF
    echo -e "\e[32m[  OK  ]\e[0m SDDM theme sidonia-no-kishi installed"
}

setup_grub_theme() {
    local theme_src="$PLUGIN_PAYLOAD/grub/sidonia-no-kishi"
    local grub_env="/etc/default/grub"
    local theme_dest="/boot/grub/themes/sidonia-no-kishi"

    [ -f "$grub_env" ] || { echo -e "\e[33m[ SKIP ]\e[0m GRUB not detected"; return 0; }
    command -v grub-mkconfig >/dev/null 2>&1 || { echo -e "\e[33m[ SKIP ]\e[0m grub-mkconfig not found"; return 0; }
    [ -d "$theme_src" ] || { echo -e "\e[33m[ SKIP ]\e[0m GRUB payload missing"; return 0; }

    if grep -q '^GRUB_THEME="/boot/grub/themes/sidonia-no-kishi/theme.txt"' "$grub_env" 2>/dev/null \
        && [ -d "$theme_dest" ] \
        && diff -r -q "$theme_src" "$theme_dest" >/dev/null 2>&1; then
        echo -e "\e[32m[  OK  ]\e[0m GRUB theme already current, skipping"
        return 0
    fi

    echo -e "\n\e[36m[ INFO ]\e[0m Configuring GRUB theme (sidonia-no-kishi)..."
    sudo cp -a "$grub_env" "$grub_env.backup.$(date +%Y%m%d_%H%M%S)"
    sudo mkdir -p "$theme_dest"
    sudo rm -rf "$theme_dest"
    sudo mkdir -p "$theme_dest"
    sudo cp -r "$theme_src/." "$theme_dest/"
    sudo chmod -R 755 "$theme_dest"

    sudo sed -i '/^[# ]*GRUB_THEME=/d' "$grub_env"
    sudo sed -i '/^[# ]*GRUB_FONT=/d' "$grub_env"
    sudo sed -i '/^[# ]*GRUB_GFXMODE=/d' "$grub_env"
    sudo sed -i 's/^#GRUB_TERMINAL_OUTPUT=.*/GRUB_TERMINAL_OUTPUT="gfxterm"/' "$grub_env"
    echo 'GRUB_THEME="/boot/grub/themes/sidonia-no-kishi/theme.txt"' | sudo tee -a "$grub_env" > /dev/null
    echo 'GRUB_FONT="/boot/grub/themes/sidonia-no-kishi/comfortaa_18.pf2"' | sudo tee -a "$grub_env" > /dev/null
    if ! sudo grep -q '^GRUB_GFXMODE=' "$grub_env"; then
        echo 'GRUB_GFXMODE="1920x1080"' | sudo tee -a "$grub_env" > /dev/null
    fi
    if ! sudo grep -q '^GRUB_TERMINAL_OUTPUT=' "$grub_env"; then
        echo 'GRUB_TERMINAL_OUTPUT="gfxterm"' | sudo tee -a "$grub_env" > /dev/null
    fi
    sudo grub-mkconfig -o /boot/grub/grub.cfg
}

setup_darkmode() {
    echo -e "\e[36m[ INFO ]\e[0m Enabling system-wide dark mode (adw-gtk3 / prefer-dark)"
    local ini_files=(
        "$HOME/.config/gtk-3.0/settings.ini"
        "$HOME/.config/gtk-4.0/settings.ini"
    )
    for f in "${ini_files[@]}"; do
        mkdir -p "$(dirname "$f")"
        if [ ! -s "$f" ]; then
            printf '[Settings]\ngtk-theme-name=adw-gtk3-dark\ngtk-application-prefer-dark-theme=true\n' > "$f"
        else
            awk -v theme="gtk-theme-name=adw-gtk3-dark" \
                -v dark="gtk-application-prefer-dark-theme=true" '
                /^\[Settings\]/ { print; print theme; print dark; next }
                /^gtk-theme-name=/ { next }
                /^gtk-application-prefer-dark-theme=/ { next }
                { print }' "$f" > "$f.tmp" && mv "$f.tmp" "$f"
            if ! grep -q '^\[Settings\]' "$f"; then
                printf '[Settings]\ngtk-theme-name=adw-gtk3-dark\ngtk-application-prefer-dark-theme=true\n' >> "$f"
            fi
        fi
    done
    gsettings set org.gnome.desktop.interface color-scheme "prefer-dark" 2>/dev/null || true
    gsettings set org.gnome.desktop.interface gtk-theme "adw-gtk3-dark" 2>/dev/null || true
}

disable_telemetry() {
    local version_file="${QS_STATE_DIR:-${XDG_STATE_HOME:-$HOME/.local/state}/serpantinum}/version"
    [ -f "$version_file" ] || return 0
    if grep -q '^ENABLE_TELEMETRY=' "$version_file"; then
        sed -i 's/^ENABLE_TELEMETRY=.*/ENABLE_TELEMETRY="false"/' "$version_file"
    else
        echo 'ENABLE_TELEMETRY="false"' >> "$version_file"
    fi
}
