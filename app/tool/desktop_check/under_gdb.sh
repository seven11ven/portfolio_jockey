#!/usr/bin/env bash
# Runs the app under gdb (gdb may trace a program it starts itself, even where
# attaching is refused). Send the app SIGINT to stop it: gdb then writes every
# thread's stack to $PJ_STACKS and ends the app. Symbol downloads are off.
exec env DEBUGINFOD_URLS= gdb -q -batch -nx \
  -ex 'set debuginfod enabled off' -ex 'set pagination off' \
  -ex 'handle SIGPIPE nostop noprint pass' -ex 'handle SIG32 nostop noprint pass' -ex 'handle SIG33 nostop noprint pass' -ex 'handle SIGPROF nostop noprint pass' -ex 'handle SIGUSR1 nostop noprint pass' -ex 'handle SIGUSR2 nostop noprint pass' \
  -ex run -ex 'info sharedlibrary' -ex 'thread apply all bt 30' -ex kill \
  --args "$@" > "${PJ_STACKS:-/dev/null}" 2>&1
