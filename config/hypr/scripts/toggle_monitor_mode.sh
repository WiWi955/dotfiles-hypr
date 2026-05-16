#!/bin/bash

# Script pour basculer entre affichage étendu et mode miroir (Hyprland)

# --- CONFIGURATION (vos moniteurs) ---
MAIN_MONITOR="eDP-1"
SECONDARY_MONITOR="HDMI-A-1"
STATE_FILE="/tmp/hypr_monitor_mode"

# --- Modes de configuration à basculer ---

# Mode 1 : ÉTENDU/SÉPARÉ (HDMI-A-1 de eDP-1)
MODE_EXTENDED() {
    echo "Passage au mode SÉPARÉ (HDMI-A-1."
    # Redéfinit l'écran principal à 0x0
    hyprctl keyword monitor "$MAIN_MONITOR, preferred, 0x0, 1"
    # Définit le moniteur secondaire à la position 1920x0 (en haut)
    hyprctl keyword monitor "$SECONDARY_MONITOR, 1920x1200@59.95000, 0x-1200, 1"

    # Définit le moniteur secondaire à la position 1920x0 (à droite) 
    #hyprctl keyword monitor "$SECONDARY_MONITOR, 1920x1200@59.95000, 1920x0, 1"

    # Définit le moniteur secondaire à la position 1920x0 (à gauche)
    #hyprctl keyword monitor "$SECONDARY_MONITOR, 1920x1200@59.95000, -1920x0, 1"
    
    echo "EXTENDED" > $STATE_FILE
}

# Mode 2 : MIROIR/DUPLIQUÉ (HDMI-A-1 duplique eDP-1)
MODE_MIRROR() {
    echo "Passage au mode MIROIR (HDMI-A-1 duplique eDP-1)."
    # Définit le moniteur secondaire en mode miroir
    hyprctl keyword monitor "$SECONDARY_MONITOR, preferred, auto, 1, mirror, $MAIN_MONITOR"
    echo "MIRROR" > $STATE_FILE
}

# --- LOGIQUE DE BASCULE ---

# Vérifie l'état actuel
CURRENT_STATE=$(cat $STATE_FILE 2>/dev/null)

if [ "$CURRENT_STATE" == "EXTENDED" ]; then
    # S'il était étendu, passe en miroir
    MODE_MIRROR
elif [ "$CURRENT_STATE" == "MIRROR" ]; then
    # S'il était en miroir, passe en étendu
    MODE_EXTENDED
else
    # Si le fichier d'état n'existe pas (premier lancement), passe en mode étendu par défaut
    MODE_EXTENDED
fi