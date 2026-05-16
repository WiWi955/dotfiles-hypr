#!/bin/bash

# ===============================================
# CONFIGURATION
# ===============================================
DOTFILES_REPO=$(pwd)
CONFIG_DIR="$HOME/.config"
SDDM_THEME="sddm-silent-theme"

# Liste des dossiers de configuration essentiels à copier
CONFIG_DIRS="cava fastfetch fish gtk-3.0 gtk-4.0 hypr kitty matugen rofi swaync waybar wlogout"

# ===============================================
# 1. PRÉREQUIS ET INSTALLATION (YAY & PKGS.txt)
# ===============================================

echo "Mise à jour du système et vérification de yay..."
sudo pacman -Syu --noconfirm

if ! command -v yay &> /dev/null; then
    echo "yay n'est pas trouvé. Installation..."
    # Installation de yay (nécessite git et base-devel)
    sudo pacman -S git base-devel --noconfirm
    git clone https://aur.archlinux.org/yay.git /tmp/yay_install
    cd /tmp/yay_install
    makepkg -si --noconfirm
    cd -
    rm -rf /tmp/yay_install
fi

echo "Installation des paquets listés dans PKGS.txt..."
# Installe les paquets AUR et officiels
yay -S --noconfirm --needed - < PKGS.txt

# ===============================================
# 2. SAUVEGARDE ET DÉPLOIEMENT DES DOTFILES
# ===============================================

echo "Sauvegarde des configurations existantes dans ~/.config_bak..."
BACKUP_DIR="$HOME/.config_bak/$(date +%Y%m%d%H%M)"
mkdir -p "$BACKUP_DIR"

# 2.1 Sauvegarde des dossiers de ~/.config
for dir in $CONFIG_DIRS; do
    if [ -d "$CONFIG_DIR/$dir" ]; then
        echo "   -> Sauvegarde de $dir"
        mv "$CONFIG_DIR/$dir" "$BACKUP_DIR/$dir"
    fi
done

echo "Déploiement des nouvelles configurations du dépôt..."

# 2.2 Copie des dossiers de config
cp -r "$DOTFILES_REPO/config/"* "$CONFIG_DIR/"

# 2.3 Copie des fichiers cachés du home (home/ vers ~)
if [ -d "$DOTFILES_REPO/home" ]; then
    echo "Déploiement des fichiers cachés du Home..."
    # L'option -f force l'écrasement des anciens fichiers
    cp -rf "$DOTFILES_REPO/home/."* "$HOME/"
fi

# ===============================================
# 3. CONFIGURATION POST-INSTALLATION
# ===============================================

# 3.1 Rendre les scripts exécutables
echo "Rendre les scripts exécutables..."
find "$CONFIG_DIR/hypr/scripts" -type f -exec chmod +x {} \;
chmod +x "$HOME/sddm-autotheme.sh"

# 3.2 Configuration et activation de SDDM
echo "Configuration de SDDM (Display Manager)..."

# Activer le service SDDM pour le démarrage automatique
sudo systemctl enable sddm

# Appliquer le thème SDDM
# Cette section modifie ou crée le fichier de configuration SDDM
if [ -f /etc/sddm.conf ]; then
    sudo sed -i "s/^Current=.*$/Current=$SDDM_THEME/" /etc/sddm.conf
    echo "Thème SDDM ($SDDM_THEME) appliqué à /etc/sddm.conf."
elif [ -d /etc/sddm.conf.d/ ]; then
    echo "[Theme]" | sudo tee /etc/sddm.conf.d/10-theme.conf > /dev/null
    echo "Current=$SDDM_THEME" | sudo tee -a /etc/sddm.conf.d/10-theme.conf > /dev/null
    echo "Thème SDDM ($SDDM_THEME) appliqué à /etc/sddm.conf.d/10-theme.conf."
else
    echo "ATTENTION : Impossible de trouver le fichier de configuration SDDM pour appliquer le thème."
fi

echo "✅ Installation complète des dotfiles terminée !"
echo "Il est FORTEMENT recommandé de REDÉMARRER votre système."
EOL
