#!/bin/bash

# Définition des chemins avec des guillemets (pour Bash)
VENV_ACTIVATE_FISH="$HOME/ESGI/Semestre1/Cryptographie/Projets/cesar/bin/activate.fish"
WORK_DIR="$HOME/ESGI/Semestre1/Cryptographie/Projets/cesar/annexe prof/script_eleve"

# --- Nouvel Ordre ---

# 1. Naviguer vers le répertoire de travail
cd "$WORK_DIR" || exit 1 # Sort si la navigation échoue

# 2. Exécuter un shell Fish, lui dire de sourcer le VENV, puis de se lancer de manière interactive.
#    C'est la commande la plus stable pour que l'activation persiste dans le shell final.
fish -c "source \"$VENV_ACTIVATE_FISH\"; exec fish"
