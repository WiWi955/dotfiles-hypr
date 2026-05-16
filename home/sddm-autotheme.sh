#!/bin/bash

# =========================================================
# SCRIPT SDDM AUTO-THEMING (PYWAL)
# - Met à jour l'accentuation Corail du thème Catppuccin
# - Dépendances : pywal, jq
# =========================================================

# --- CONFIGURATION ---
# Chemin des composants QML
THEME_DIR="/usr/share/sddm/themes/catppuccin-mocha-mauve/Components/"

# COULEURS ORIGINALES À REMPLACER
OLD_ACCENT="#ffb4ab" 
OLD_HOVER_ACCENT="Qt.rgba(1, 0.70, 0.67, 0.5)"
OLD_TRANSPARENT="Qt.rgba(0.2, 0.2, 0.2, 0.3)"

# --- GÉNÉRATION DES NOUVELLES COULEURS ---
# S'assurer que le fichier de cache de Pywal existe
if [ ! -f ~/.cache/wal/colors.json ]; then
    echo "Erreur: Les couleurs Pywal n'ont pas été générées. Exécutez 'wal -i /chemin/vers/votre/fond.png' d'abord."
    exit 1
fi

# Récupérer la nouvelle couleur d'accentuation (Pywal color5)
NEW_ACCENT=$(cat ~/.cache/wal/colors.json | jq -r '.colors.color5')

# Conserver un fond sombre transparent fixe (pour l'effet glassmorphism)
# Nous allons juste mettre à jour l'ancien fond transparent pour qu'il soit plus sombre
NEW_TRANSPARENT="Qt.rgba(0.06, 0.06, 0.1, 0.3)"

# --- FONCTION DE REMPLACEMENT ---
# $1: Fichier QML à modifier
replace_colors() {
    echo "Mise à jour de $1..."
    
    # Remplacer l'ACCENT CORAIL (#ffb4ab) par le nouvel accent Pywal (Opaque)
    sudo sed -i "s/${OLD_ACCENT}/${NEW_ACCENT}/g" "$1"

    # Remplacer la couleur de survol Corail Transparent (OLD_HOVER_ACCENT) par le nouvel accent Pywal (Opaque)
    # *Note : Ceci désactive la transparence du survol. Le survol sera l'accent Pywal opaque.*
    sudo sed -i "s/${OLD_HOVER_ACCENT}/${NEW_ACCENT}/g" "$1"
    
    # Remplacer le fond sombre transparent du panneau (OLD_TRANSPARENT) par le nouveau fond transparent
    sudo sed -i "s/${OLD_TRANSPARENT}/${NEW_TRANSPARENT}/g" "$1"
}

# --- EXÉCUTION ---
echo "Nouvelle couleur d'accent Pywal : ${NEW_ACCENT}"

# Liste des fichiers QML à modifier
FILES=(
    "${THEME_DIR}Clock.qml"
    "${THEME_DIR}LoginPanel.qml"
    "${THEME_DIR}PowerButton.qml"
    "${THEME_DIR}RebootButton.qml"
    "${THEME_DIR}SleepButton.qml"
    "${THEME_DIR}UserField.qml"
    "${THEME_DIR}PasswordField.qml"
    "${THEME_DIR}SessionButton.qml"
)

for FILE in "${FILES[@]}"; do
    replace_colors "$FILE"
done

# --- REDÉMARRAGE SDDM ---
echo "Redémarrage de SDDM..."
sudo systemctl restart sddm

echo "Fini. Le nouveau thème est actif."
