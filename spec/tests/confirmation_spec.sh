#!/usr/bin/env sh
# spec/confirmation_spec.sh

. spec/spec_helper.sh

Describe "confirmation_POSIX.sh interactive prompt"

  It "exits 0 and prints success message when user types the exact word ERASE"
    When run sh -c 'printf "ERASE\n" | sh function/confirmation_POSIX.sh'
    The status should be success
    The output should include "Confirmation accepted."
  End

  It "exits 1 and prints abort message when user types something else"
    When run sh -c 'printf "WRONG\n" | sh function/confirmation_POSIX.sh'
    The status should be failure
    The output should include "Invalid confirmation."
  End

  It "exits 1 and prints abort message when user types CTRL+C"
    When run sh -c 'printf "\003" | sh function/confirmation_POSIX.sh'
    The status should be failure
    The output should include "Operation canceled by user."
  End

  It "exits 1 and prints abort message when user types CTRL+D"
    When run sh -c 'printf "\004" | sh function/confirmation_POSIX.sh'
    The status should be failure
    The output should include "Operation canceled by user."
  End

  It "exits 1 and prints abort message when user types ESC"
    When run sh -c 'printf "\033" | sh function/confirmation_POSIX.sh'
    The status should be failure
    The output should include "Operation canceled by user."
  End

End