#!/bin/bash
# Redéploie cette config sur un PC Omarchy fraîchement installé.
#   ./install.sh            paquets + config + services
#   ./install.sh --no-pkgs  config + services seulement
set -euo pipefail
cd "$(dirname "$(readlink -f "$0")")"

# 1. Paquets en plus de ceux d'Omarchy
if [[ ${1-} != --no-pkgs ]]; then
  mapfile -t pkgs < <(grep -vE '^\s*(#|$)' packages.txt)
  echo "==> Installation des paquets : ${pkgs[*]}"
  omarchy pkg aur add "${pkgs[@]}"
fi

# 2. Sauvegarde puis copie de la config
backup="$HOME/.dotfiles-backup/$(date +%Y%m%d-%H%M%S)"
echo "==> Sauvegarde de l'existant dans $backup"
grep -vE '^\s*(#|$)' files.txt | while read -r path; do
  [[ -e home/$path ]] || continue
  if [[ -e $HOME/$path ]]; then
    mkdir -p "$backup/$(dirname "$path")"
    cp -a "$HOME/$path" "$backup/$(dirname "$path")/"
  fi
  mkdir -p "$HOME/$(dirname "$path")"
  cp -a "home/$path" "$HOME/$(dirname "$path")/"
done
chmod +x "$HOME"/.local/bin/{wiwi-*,ia,lab-ia-status,nas-status,pc-status} \
  "$HOME/.config/omarchy/plugins/will.monitor/display-ctl" \
  "$HOME/.config/omarchy/hooks/theme-set.d/wiwi-stop-animated-bg"
mkdir -p "$HOME/.local/state/wiwi-bg" "$HOME/GoogleDrive"

# 3. Services utilisateur
echo "==> Activation des services"
systemctl --user daemon-reload
systemctl --user enable --now wiwi-bg-sync.path wiwi-wallpaper-colors.path
systemctl --user enable wiwi-mpvpaper.service voxtype.service
if [[ -f $HOME/.config/rclone/rclone.conf ]]; then
  systemctl --user enable --now rclone-gdrive.service
else
  echo "   rclone non configuré : lance 'rclone config' (remote « gdrive »), puis"
  echo "   systemctl --user enable --now rclone-gdrive.service"
fi

# 4. Thème
echo "==> Application du thème wiwi"
omarchy theme set wiwi || true
hyprctl reload >/dev/null 2>&1 || true

echo
echo "Terminé. Déconnecte-toi / reconnecte-toi pour tout recharger."
echo "Les vidéos de fond (.mp4) ne sont pas dans le dépôt : remets-les dans"
echo "  ~/.config/omarchy/themes/wiwi/backgrounds/"
