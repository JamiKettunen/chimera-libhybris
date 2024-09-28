# halium.sh
export EGL_PLATFORM='hwcomposer'

# If not running interactively, don't do anything else
case $- in
  *i*) : ;;
  *) return ;;
esac

if [ ! -f /.chimera_hide_libhybris_notice ]; then
    echo -e "
Welcome to \e[35m\e]8;;https://chimera-linux.org\aChimera Linux\e]8;;\a\e[0m (with \e[32m\e]8;;https://github.com/libhybris/libhybris\alibhybris\e]8;;\a\e[0m) on kernel \e[1;33m$(uname -r)\e[0m! ^^

\e[31mPlease \e[1mDO NOT\e[0m\e[31m report any issues to upstream Chimera Linux, they're not
responsible for anything in particular until confirmed it's for sure not
libhybris/downstream kernel etc related!\e[0m

For some further reading see https://halium.org, https://chimera-linux.org
and https://github.com/JamiKettunen/chimera-libhybris"
fi
