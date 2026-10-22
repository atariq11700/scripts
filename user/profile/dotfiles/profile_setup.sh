#!/bin/bash

# ==============================================================================
# Filename:         profile_setup.sh
# Description:      Symlink the dotfiles into $HOME and source the resulting
#                   .bashrc.
# Author:           Adam A https://github.com/atariq11700
# Date Created:     2026-10-21
# License:          AGPL-3.0
# ==============================================================================

if [[ "$OSTYPE" == "msys" ||  "$OSTYPE" == "win32" ]]; then
    export MSYS=winsymlinks:nativestrict
fi

files=(.bashrc)
for file in "${files[@]}"; do
    if [[ ! -f "$HOME/$file" ]]; then
        ln -s "$PWD/$file" "$HOME/$file"
    fi
done

source "$HOME/.bashrc"

check_prog_exists() {
    which "$1" > /dev/null
    if [[ $? -ne 0 ]]; then
        if [[ "$2" == "btop" ]]; then
            echo "$2 not found. Please install it and symlink it to $1.\n"
        else
            echo "$1 not found. Please install it.\n"
        fi
        return 1
    fi

    return 0
}

if [[ "$OSTYPE" == "linux-gnu"* ]]; then
    sudo apt update
    sudo apt upgrade -y --fix-missing
    ret=$(check_prog_exists btop)
    ret+=$(check_prog_exists autossh)
    ret+=$(check_prog_exists ccze)
    ret+=$(check_prog_exists bat batcat)
    ret+=$(check_prog_exists fzf)

    if [[ ret -gt 0 ]]; then
        echo "Exiting due to dependency errors"
        exit 1
    fi

    if [[ ! -d "$HOME"/.local/bin ]]; then
        mkdir -p "$HOME"/.local/bin
    fi

    if [[ ! -f "$HOME"/.local/bin/bat ]]; then
        ln -s /usr/bin/batcat "$HOME"/.local/bin/bat
    fi

    cat /etc/inputrc | grep -q "set completion-ignore-case on"
    if [[ $? -ne 0 ]]; then
        echo set completion-ignore-case on | sudo tee -a /etc/inputrc
    fi

fi

if [[ ! -d "$HOME/.config" ]]; then
    mkdir "$HOME/.config"
fi

if [[ ! -f "$HOME/.config/vscode-custom-styles.css" ]]; then
    ln -s "$TOOLSDIR/vscode-customs/vscode-custom-styles.css" "$HOME/.config/vscode-custom-styles.css"
fi

# Setup git stuff
git config --global pull.rebase true