#!/usr/bin/env sh
# spec/tests/terminal_lib_spec/test_helpers.sh

# File: is_interactive_terminal.sh
# Desc: Test helper to execute terminal functions in a true subshell.
# Author: Joseph Mowery <mowery.joseph@outlook.com>

. libs/terminal_lib.sh

case "$1" in
    "non-interactive-test")
        is_interactive_terminal < /dev/null
        exit $?
        ;;
    "show-state")
        echo "stdin_is_tty:$([ -t 0 ] && echo "yes" || echo "no")"
        is_interactive_terminal && echo "function_result:interactive" || echo "function_result:non-interactive"
        ;;
    *)
        echo "Usage: $0 {non-interactive-test|show-state}"
        exit 1
        ;;
esac