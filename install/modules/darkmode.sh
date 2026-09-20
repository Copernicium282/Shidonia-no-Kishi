#!/usr/bin/env bash

apply_gsettings() {
    local schema="$1" key="$2" value="$3"
    if gsettings set "$schema" "$key" "$value" 2>/dev/null; then
        return 0
    fi
    if command -v dbus-run-session >/dev/null 2>&1; then
        dbus-run-session gsettings set "$schema" "$key" "$value" 2>/dev/null
    fi
    return 0
}

setup_darkmode() {
    echo -e "\n\e[36m[ INFO ]\e[0m Enabling system-wide dark mode (adw-gtk3 / prefer-dark)"

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

    apply_gsettings org.gnome.desktop.interface color-scheme "prefer-dark"
    apply_gsettings org.gnome.desktop.interface gtk-theme "adw-gtk3-dark"
}