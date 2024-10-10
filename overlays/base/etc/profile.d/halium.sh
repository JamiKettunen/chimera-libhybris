# halium.sh
export EGL_PLATFORM='hwcomposer'

# If not running interactively, don't do anything else
case $- in
  *i*) : ;;
  *) return ;;
esac

if [ ! -f /run/dinit/failed-boot ]; then
  # give at least a clear hint when the Halium container boot process could have problems
  if [ ! -f /run/dinit/completed-boot ]; then
    echo -e "\e[1;33mNOTICE: The system is still booting (android.target not reached)\e[0m\n"
  fi
  # prompt about running initial tests on first successful boot (not dinit-panic) and when not yet asked
  if [ -f /run/dinit/first-boot ] && [ ! -f /tmp/.chimera_no_libhybris_tests ]; then
      touch /tmp/.chimera_no_libhybris_tests
      read -p 'Run quick initial boot libhybris/Halium Android container tests (Y/n)? ' ans
      case "${ans^^}" in 'Y'*|'') doas chimera-libhybris-tests ;; esac
  fi
fi

echo -e "Welcome to \e[35m\e]8;;https://chimera-linux.org\aChimera Linux\e]8;;\a\e[0m (with \e[32m\e]8;;https://github.com/libhybris/libhybris\alibhybris\e]8;;\a\e[0m) on kernel \e[1;33m$(uname -r)\e[0m ($(uptime -p))! ^^"

if [ ! -f /.chimera_hide_libhybris_notice ]; then
  echo -e "
\e[31mPlease \e[1mDO NOT\e[0m\e[31m report any issues to upstream Chimera Linux, they're not
responsible for anything in particular until confirmed it's for sure not
libhybris/downstream kernel etc related!\e[0m

For some further reading see https://halium.org, https://chimera-linux.org
and https://github.com/JamiKettunen/chimera-libhybris

To conduct some tests for an initial port run \e[1mdoas chimera-libhybris-tests\e[0m

Once you understand this you may hide most of this with \e[1mdoas touch /.chimera_hide_libhybris_notice\e[0m"
fi
