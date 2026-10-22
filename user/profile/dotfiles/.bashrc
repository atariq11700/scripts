#!/bin/bash

# ==============================================================================
# Filename:         .bashrc
# Description:      Shared bash profile that sets TOOLSDIR and sources per-host and
#                   per-OS settings.
# Author:           Adam A https://github.com/atariq11700
# Date Created:     2026-10-21
# License:          AGPL-3.0
# ==============================================================================

TOOLSDIR="$(dirname "$(dirname "$(readlink -f "${BASH_SOURCE[0]}")")")"
export TOOLSDIR

# Get machine specific stuff
if [[ -f "$TOOLSDIR/dotfiles/.bashrc_$HOSTNAME" ]]; then
    source "$TOOLSDIR/dotfiles/.bashrc_$HOSTNAME"
fi

# Windows specific stuff
if [[ "$OSTYPE" == "msys" ||  "$OSTYPE" == "win32" ]]; then
    echo ""
fi

# Linux specific stuff
if [[ $OSTYPE == "linux-gnu"* ]]; then
    alias armobjdump='arm-linux-gnueabi-objdump -D'
    alias s='systemctl'
    alias j='journalctl'

    if [ -d "/usr/local/go/bin" ]; then
    export PATH=$PATH:/usr/local/go/bin
    fi

    # Autossh stuff
    export AUTOSSH_POLL=5
    export AUTOSSH_GATETIME=0

    alias assh='autossh -t'
    function asshw(){
        echo -ne "\033]0;$1 - $2\a"
        if [[ -n "$2" ]]; then
            autossh -t "$1" "journalctl --no-tail -afu $2" | ccze -A
        else
            autossh -t "$1" "journalctl --no-tail -af" | ccze -A
        fi
    }
fi

# shellcheck disable=SC1091
source "$TOOLSDIR/dotfiles"/git-prompt.sh
# shellcheck disable=SC1091
source "$TOOLSDIR/dotfiles"/git-completion.bash

# for displaying git branch in terminal
parse_git_branch() {
    git branch 2> /dev/null | sed -e '/^[^*]/d' -e 's/* \(.*\)/ (\1)/'
}

get_git_repo_url_ps1() {
    # Single git call: get all remote URLs, parse in pure bash (no sed/grep)
    local line name url remote_count=0 origin_url="" first_name="" first_url=""
    while IFS= read -r line; do
        name=${line%%.url *}
        name=${name#remote.}
        url=${line#*.url }
        ((remote_count++))
        [[ $remote_count -eq 1 ]] && first_name=$name && first_url=$url
        [[ $name == origin ]] && origin_url=$url
    done < <(git config --get-regexp '^remote\..*\.url$' 2>/dev/null)

    [[ $remote_count -eq 0 ]] && return

    local remote_name url_chosen
    if [[ -n $origin_url ]]; then
        remote_name="origin"
        url_chosen=$origin_url
    else
        remote_name=$first_name
        url_chosen=$first_url
    fi

    # strip protocol+host (https://host/path) or scp-style (git@host:path)
    local repo_alias=${url_chosen#*//*/}
    [[ $repo_alias == "$url_chosen" ]] && repo_alias=${url_chosen#*:}

    [[ -z $repo_alias ]] && return

    local ret_string=" ("
    [[ $remote_count -gt 1 ]] && ret_string+="[$remote_count]"
    [[ $remote_name != origin ]] && ret_string+="${remote_name}@"
    ret_string+="$repo_alias)"

    printf '%s' "$ret_string"
}

PS1='\n[$HOST_NICKNAME]'
if [[ -v HOST_DNAME ]]; then
	PS1="$PS1"' [$HOST_DNAME]'
fi
PS1="$PS1"' ${debian_chroot:+($debian_chroot)}'
PS1="$PS1$HOST_COLOR"'\u@\h\[\033[00m\]'
if [[ "$OSTYPE" == "msys" ||  "$OSTYPE" == "win32" ]]; then
PS1="$PS1"' \[\033[01;35m\]$MSYSTEM'
fi
PS1="$PS1"' \[\033[01;34m\]\w\[\033[00m\]'
PS1="$PS1"'`get_git_repo_url_ps1`'
PS1="$PS1"'`__git_ps1`'
PS1="$PS1"'\n'
PS1="$PS1"'\$ '

# Aliases
alias ls='ls -lah --group-directories-first --color=auto'
alias da='deactivate'
alias suir='git submodule update --init --recursive'
alias gfps='git fetch && git pull --rebase && suir'
alias check_submodules="\$TOOLSDIR/scripts/submodule_tags.sh -c -r "

bashrc() {
    if [[ -z $1 ]]; then
        # shellcheck disable=SC1091
        nano "$HOME"/.bashrc && source "$HOME"/.bashrc
        return
    fi

    # shellcheck disable=SC1091
    nano "$TOOLSDIR/dotfiles"/.bashrc_"$1" && source "$HOME"/.bashrc
}

#Vscode Integrated Terminal Compatability Fix
export PROMPT_COMMAND='history -a'

# Fzf stuff
_gen_fzf_color_opts() {
    #   local base03="234"
    #   local base02="235"
    #   local base01="240"
    #   local base00="241"
    #   local base0="244"
    #   local base1="245"
    #   local base2="254"
    #   local base3="230"
    #   local yellow="136"
    #   local orange="166"
    #   local red="160"
    #   local magenta="125"
    #   local violet="61"
    #   local blue="33"
    #   local cyan="37"
    #   local green="64"

    #   Uncomment for truecolor, if your terminal supports it.
    local base03="#002b36"
    local base02="#073642"
    local base01="#586e75"
    local base00="#657b83"
    local base0="#839496"
    local base1="#93a1a1"
    local base2="#eee8d5"
    local base3="#fdf6e3"
    local yellow="#b58900"
    local orange="#cb4b16"
    local red="#dc322f"
    local magenta="#d33682"
    local violet="#6c71c4"
    local blue="#268bd2"
    local cyan="#2aa198"
    local green="#859900"

    # Comment and uncomment below for the light theme.

    # Solarized Dark color scheme for fzf
    export FZF_DEFAULT_OPTS="
    --color fg:-1,bg:-1,hl:$blue,fg+:$base2,bg+:$base02,hl+:$blue
    --color info:$yellow,prompt:$yellow,pointer:$base3,marker:$base3,spinner:$yellow
    "                                                                                                                  ## Solarized Light color scheme for fzf
    #export FZF_DEFAULT_OPTS="
    #  --color fg:-1,bg:-1,hl:$blue,fg+:$base02,bg+:$base2,hl+:$blue
    #  --color info:$yellow,prompt:$yellow,pointer:$base03,marker:$base03,spinner:$yellow
    #"
}

[ -f ~/.fzf.bash ] && source ~/.fzf.bash
_gen_fzf_color_opts

export FZF_DEFAULT_OPTS="$FZF_DEFAULT_OPTS --border='rounded' --border-label='$(pwd)' --ansi --tabstop=4 --color='label:cyan' --preview='bat --color=always {}'"
fz() {
    path=""
    ret=0

    #handle all app specific fzf setup/use

    #if cd, then search through directories
    if [ "$1" == "cd" ]; then
        path=$(find ./ -type d | fzf)
    #all others use default search
    else
        path=$(fzf)
    fi

    if [ $? != 0 ]; then
        return $?
    fi

    path=$(echo "$path" | sed 's/\\/\//g')

    #make sure path was chosen
    ret=$?
    if [ $ret != 0 ]; then
        return $ret
    fi

    #if no command be normal fzf
    if [ -z "$1" ]; then
        echo "$path"
        return
    fi

    if [ "$1" == "cdf" ]; then
        cd "$(dirname "$path")" || return
    else
        #execute command with path
        "$1" "$path" "${@:2}"
    fi
}
