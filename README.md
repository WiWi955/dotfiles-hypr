# dotfiles-hypr — config Omarchy de WiWi

Ma config [Omarchy](https://omarchy.org/) (Arch + Hyprland) : raccourcis, barre et widgets,
thème `wiwi` avec couleurs générées depuis le fond d'écran, fonds animés, scripts perso.

> L'ancienne config (Hyprland + Waybar + Rofi, avant Omarchy) est sur la branche [`legacy`](../../tree/legacy).

## Installation sur un nouveau PC

1. Installer Omarchy normalement.
2. Puis :
   ```bash
   git clone git@github.com:WiWi955/dotfiles-hypr.git ~/dotfiles-hypr
   cd ~/dotfiles-hypr
   ./install.sh            # paquets + config + services
   # ./install.sh --no-pkgs  pour ne copier que la config
   ```
3. Se déconnecter / reconnecter.

L'ancienne config de la machine est sauvegardée dans `~/.dotfiles-backup/<date>/` avant d'être remplacée.

**À faire à la main après l'installation :**
- `rclone config` (remote nommé `gdrive`) puis `systemctl --user enable --now rclone-gdrive.service`
- Remettre les vidéos de fond (`.mp4`, trop lourdes pour GitHub) dans `~/.config/omarchy/themes/wiwi/backgrounds/`
- `~/.ssh/config` avec les hôtes `nas` et `ia` (utilisés par `SUPER+N`, `SUPER+I` et le widget lab-ia)
- Adapter `hypr/monitors.lua`, `hypr/display.lua` et `omarchy/display-layout.json` si les écrans sont différents
- Le raccourci `SUPER+W` pointe vers `/home/will/...` : à corriger si le nom d'utilisateur change

## Mettre à jour le dépôt

Après avoir modifié la config sur ce PC :
```bash
cd ~/dotfiles-hypr
./sync.sh        # recopie la config du PC dans le dépôt
git add -A && git commit -m "maj config" && git push
```
Les fichiers suivis sont listés dans [`files.txt`](files.txt) ; ajoute une ligne pour suivre un nouveau fichier.

## Contenu

| Élément | Où |
| :--- | :--- |
| Raccourcis clavier | `.config/hypr/bindings.lua` |
| Règles de fenêtres, opacité, anti-veille YouTube | `.config/hypr/hyprland.lua` |
| Look & feel, clavier/souris, écrans | `.config/hypr/{looknfeel,input,monitors,display}.lua` |
| Barre + widgets, veille/verrouillage | `.config/omarchy/shell.json` |
| Widgets perso | `.config/omarchy/plugins/will.lab-ia` (serveur IA / NAS / PC), `will.monitor` (écrans), `will.todo` (to-do) |
| Menu | `.config/omarchy/extensions/omarchy-menu.jsonc` |
| Thème | `.config/omarchy/themes/wiwi` (couleurs via matugen) |
| Fonds animés / sélecteur | `.local/bin/wiwi-*` + services `wiwi-*` dans `.config/systemd/user` |
| Prompt bash + fastfetch, commandes `list` / `add` (to-do) | `.bashrc`, `.config/fastfetch/banner.jsonc` |
| Dictée vocale | `.config/voxtype/config.toml` |
| Paquets en plus d'Omarchy | `packages.txt` |

## Raccourcis principaux

| Touches | Action |
| :--- | :--- |
| `SUPER+Q` / `SUPER+SHIFT+Q` | Fermer / tuer la fenêtre |
| `SUPER+D` | Lanceur d'applis |
| `SUPER+SHIFT+Entrée` | Terminal flottant |
| `SUPER+B` | Navigateur (workspace 3) |
| `SUPER+E` / `SUPER+SHIFT+E` | Fichiers (workspace 2) / nouvelle fenêtre |
| `SUPER+SHIFT+D` | Discord (workspace 4) |
| `SUPER+O` | Obsidian |
| `SUPER+CTRL+S` | Steam |
| `SUPER+N` / `SUPER+I` | SSH NAS / serveur IA (réveil Wake-on-LAN) |
| `SUPER+ALT+I` | Widget lab-ia / NAS |
| `SUPER+T` | Widget to-do |
| `SUPER+SHIFT+T` | Fenêtre flottante / en mosaïque |
| `SUPER+W` | Sélecteur de fond d'écran (images + vidéos) |
| `SUPER+L` | Verrouiller |
| `SUPER+SHIFT+S` | Capture d'écran |
| `SUPER+C` | Pipette à couleur |
| `SUPER+V` | Historique du presse-papier |
| `SUPER+R` | Redémarrer la barre |
| `SUPER+M` | Recopie d'écran on/off |
| `SUPER+CTRL+Flèches` | Déplacer la fenêtre |
| `SUPER+SHIFT+Flèches` | Redimensionner la fenêtre |
| `CTRL+SHIFT+Espace` (maintenir) | Dictée vocale |
| `CTRL+ALT+Suppr` | Quitter Hyprland |
