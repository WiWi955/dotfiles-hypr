#!/bin/bash
# Copie la config actuelle de ce PC dans le dépôt (à lancer avant un commit).
set -euo pipefail
cd "$(dirname "$(readlink -f "$0")")"

rm -rf home
grep -vE '^\s*(#|$)' files.txt | while read -r path; do
  [[ -e $HOME/$path ]] || { echo "absent, ignoré : $path"; continue; }
  mkdir -p "home/$(dirname "$path")"
  rsync -a \
    --exclude '*.bak.*' --exclude '*.orig' --exclude '__pycache__' \
    --exclude '*.mp4' --exclude '*.webm' --exclude '*.mkv' --exclude '*.mov' \
    "$HOME/$path" "home/$(dirname "$path")/"
done
echo "Synchronisé. Vérifie avec : git status"
