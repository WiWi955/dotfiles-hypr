# 🚀 Mes Dotfiles Arch Linux Hyprland

Bienvenue dans mon dépôt de dotfiles ! Ces configurations sont optimisées pour **Arch Linux** utilisant le compositeur **Hyprland**.

## ✨ Aperçu des Composants

| Composant | Rôle |
| :--- | :--- |
| **Compositeur** | **Hyprland** (Tiling Window Manager pour Wayland) |
| **Barre** | **Waybar** (personnalisée et modulaire) |
| **Lanceur** | **Rofi** |
| **Terminal** | **Kitty** |
| **Notifications** | **SwayNC** (Wayland Notification Center) |
| **Thème** | **Matugen** et **Catppuccin** (pour l'auto-theming et l'apparence) |
| **Display Manager** | **SDDM** avec le thème `sddm-silent-theme` |
| **Shell** | **Fish** (avec configuration dans `config/fish`) |

## 🛠️ Dépendances

La liste complète des paquets requis (officiels et AUR) se trouve dans [PKGS.txt](./PKGS.txt).

Les principaux utilitaires que ce setup utilise sont : `hyprland`, `waybar`, `rofi`, `kitty`, `swww`, `grim`, `slurp`, `wlogout`, `matugen-bin`, `sddm-silent-theme`.

## ⬇️ Instructions d'Installation Automatisée

Le script `./install.sh` automatise tout : installation de **yay**, des paquets listés, sauvegarde de vos anciennes configs, déploiement des nouvelles, et activation de SDDM.

**AVERTISSEMENT :** L'exécution de ce script va **écraser** les fichiers de configuration existants dans votre `~/.config/` et `~/.home/`. Une sauvegarde est créée dans `~/.config_bak/`.

### Préparation (Sur une Arch Linux minimale)

1.  **Cloner le dépôt :** Installez `git` si ce n'est pas fait (`sudo pacman -S git`).
    ```bash
    git clone [https://github.com/VotreNomUtilisateur/votre-depot-dotfiles.git](https://github.com/VotreNomUtilisateur/votre-depot-dotfiles.git)
    cd votre-depot-dotfiles
    ```

### Lancement

2.  **Lancer le script d'installation :**
    ```bash
    chmod +x install.sh
    ./install.sh
    ```
    *(Le script s'occupera d'installer `yay` puis tous les paquets de `PKGS.txt`, de copier les configs, et d'activer SDDM.)*

### Après Installation

3.  **Redémarrage :** Déconnectez-vous ou redémarrez le système pour que SDDM et Hyprland puissent démarrer correctement.
    ```bash
    reboot
    ```
