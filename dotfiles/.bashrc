#
# ~/.bashrc
#

# If not running interactively, don't do anything
[[ $- != *i* ]] && return

# Craft the prompt.
[ 'id -u' = '0' ] && PS1='$\e[0;31m$HOSTNAME$\e[0;34m [\w] #\e[0m'||
PS1='\e[0;32m\u@\h\e[0;34m [\w] $\e[0m'
PS1=${PS1}'\n> '

#[ 'id -u' = '0' ] && PS1='[$PWD] # > ' || PS1='[$PWD] $ > '
#PS2='> '
#export PS1 PS2

# General env vars.
export HISTSIZE=2000

# Aliases to soft-replace GNU coreutils with uutils.
#for coreutils_util in /usr/bin/uu-*; do
#	alias "$(echo $coreutils_util | cut -d '-' -f2)"="$coreutils_util"
#done

# Other aliases.
alias ls='exa --color-scale --sort=type --group-directories-first'
alias sudo='doas'
alias sudoedit='doas rnano'

# Start desktop environment.
if [ -z $DISPLAY ] && [ "$(tty)" = "/dev/tty1" ]; then
  #exec sway
  exec ~/.config/lock.sh &
  exec /usr/lib/plasma-dbus-run-session-if-needed startplasma-wayland
  #exec start-cosmic
fi

# Mute all microphones using pactl
if [[ $USER != "work" ]]; then
  pactl list short sources | while read source; do
    source_id=$(echo $source | cut '-d ' -f1)
    pactl set-source-volume $source_id 0%
  done
fi
