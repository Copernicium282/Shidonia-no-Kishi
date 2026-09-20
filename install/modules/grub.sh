#!/usr/bin/env bash

setup_grub() {
    local project_root="$1"
    local theme_src="$project_root/config/grub/themes/sidonia-no-kishi"
    local grub_env="/etc/default/grub"

    if [ ! -f "$grub_env" ]; then
        echo -e "\e[33m[ SKIP ]\e[0m GRUB not detected (/etc/default/grub missing), skipping GRUB theme"
        return 0
    fi

    if ! command -v grub-mkconfig >/dev/null 2>&1; then
        echo -e "\e[33m[ SKIP ]\e[0m grub-mkconfig not found, skipping GRUB theme"
        return 0
    fi

    if [ ! -d "$theme_src" ]; then
        echo -e "\e[33m[ SKIP ]\e[0m Bundled GRUB theme not found ($theme_src)"
        return 0
    fi

    echo -e "\n\e[36m[ INFO ]\e[0m Configuring GRUB theme (sidonia-no-kishi)..."

    sudo cp -a "$grub_env" "$grub_env.backup.$(date +%Y%m%d_%H%M%S)"

    sudo mkdir -p /boot/grub/themes
    sudo rm -rf /boot/grub/themes/sidonia-no-kishi
    sudo mkdir -p /boot/grub/themes/sidonia-no-kishi
    sudo cp -r "$theme_src/." /boot/grub/themes/sidonia-no-kishi/
    sudo chmod -R 755 /boot/grub/themes/sidonia-no-kishi

    local grub_font="/boot/grub/themes/sidonia-no-kishi/comfortaa_18.pf2"

    sudo sed -i '/^[# ]*GRUB_THEME=/d' "$grub_env"
    sudo sed -i '/^[# ]*GRUB_FONT=/d' "$grub_env"
    sudo sed -i '/^[# ]*GRUB_GFXMODE=/d' "$grub_env"
    sudo sed -i 's/^#GRUB_TERMINAL_OUTPUT=.*/GRUB_TERMINAL_OUTPUT="gfxterm"/' "$grub_env"

    echo 'GRUB_THEME="/boot/grub/themes/sidonia-no-kishi/theme.txt"' | sudo tee -a "$grub_env" > /dev/null
    echo "GRUB_FONT=\"$grub_font\"" | sudo tee -a "$grub_env" > /dev/null

    if ! sudo grep -q '^GRUB_GFXMODE=' "$grub_env"; then
        echo 'GRUB_GFXMODE="1920x1080"' | sudo tee -a "$grub_env" > /dev/null
    fi
    if ! sudo grep -q '^GRUB_TERMINAL_OUTPUT=' "$grub_env"; then
        echo 'GRUB_TERMINAL_OUTPUT="gfxterm"' | sudo tee -a "$grub_env" > /dev/null
    fi

    sudo grub-mkconfig -o /boot/grub/grub.cfg
}