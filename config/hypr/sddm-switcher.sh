#!/bin/bash

PROFILE_NAME="$1"
SOURCE_DIR="$HOME/sddm-profiles/${PROFILE_NAME}"
TARGET_SDDM_THEME_DIR="/usr/share/sddm/themes/catppuccin" 
TARGET_KITTY_CONF="$HOME/.config/kitty/current_color_profile.conf" 

if [ -z "$PROFILE_NAME" ]; then
    echo "ERREUR: Veuillez spécifier le nom du profil."
    exit 1
fi

if [ ! -d "$SOURCE_DIR" ]; then
    echo "ERREUR: Le profil de couleur '$PROFILE_NAME' n'existe pas."
    exit 1
fi

echo "Application du profil '$PROFILE_NAME'..."

# --- 1. Mise à jour du thème SDDM ---
echo "Mise à jour des fichiers QML et config SDDM..."

# Copie les QML (boutons, champs)
sudo cp -rfT "$SOURCE_DIR/Components" "$TARGET_SDDM_THEME_DIR/Components"

# Copie le Main.qml (le fond de repli)
sudo cp -f "$SOURCE_DIR/Main.qml" "$TARGET_SDDM_THEME_DIR/Main.qml"

# Copie le theme.conf (image de fond, etc.)
sudo cp -f "$SOURCE_DIR/theme.conf" "$TARGET_SDDM_THEME_DIR/theme.conf"


# --- 2. Mise à jour de la couleur Kitty (si le fichier existe) ---
if [ -f "$SOURCE_DIR/kitty-colors.conf" ]; then
    echo "Mise à jour du fichier de couleurs Kitty..."
    cp "$SOURCE_DIR/kitty-colors.conf" "$TARGET_KITTY_CONF"
fi

# --- 3. Redémarrage de SDDM ---
echo "Redémarrage de SDDM..."
sudo systemctl restart sddm

echo "Thème SDDM mis à jour avec le profil $PROFILE_NAME."
