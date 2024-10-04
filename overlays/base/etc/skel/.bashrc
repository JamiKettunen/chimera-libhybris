# ~/.bashrc

# If not running interactively, don't do anything else
# TODO: is this even needed here?
#[[ $- != *i* ]] && return

# FIXME: the colored prompts break line editing with wrapping long lines?!
# -> due to missing locale stuff?
#PS1='\u@\h:\W\$ '
if [ $EUID -eq 0 ]; then
    PS1='\[\e[31m\]\u\[\e[0m\]@\[\e[35m\]\h\[\e[0m\]:\[\e[36m\]\W\[\e[0m\]\$ '
else
    PS1='\[\e[32m\]\u\[\e[0m\]@\[\e[35m\]\h\[\e[0m\]:\[\e[36m\]\W\[\e[0m\]\$ '
fi

complete -cf doas sudo time strace

export HISTCONTROL=ignoredups:erasedups \
	HISTSIZE=10000 \
	HISTFILESIZE=10000

alias \
	ls='ls --color' \
	sudo='doas' \
	cat='cat -v'

[ -f ~/.bash_aliases ] && . ~/.bash_aliases
