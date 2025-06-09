#!/usr/bin/env sh
# spec/tests/terminal_lib_spec/is_interactive_terminal.sh

# File: is_interactive_terminal.sh
# Desc: Unit tests for the function is_interactive_terminal in terminal_lib.sh library.
# Author: Joseph Mowery <mowery.joseph@outlook.com>

# Function Under Test:
# is_interactive_terminal() {
#     [ -t 0 ]
# }

. spec/spec_helper.sh

Describe 'Terminal Detection Diagnostics'

  It 'returns true when run in an interactive shell'
    When call sh -c '. libs/terminal_lib.sh; is_interactive_terminal'
    The status should equal 0
  End

  It 'returns false when stdin is piped'
    When call sh -c 'echo "test input" | sh -c ". libs/terminal_lib.sh; is_interactive_terminal"'
    The status should not equal 0
  End

End