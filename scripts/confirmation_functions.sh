#!/usr/bin/env bash

# File: confirmation_functions.sh
# Desc: Stylized interactive confirmation prompt.
# Author: Joseph Mowery
# Email: mowery.joseph@outlook.com

# ================================= #
# STRICT MODE AND ENVIRONMENT SETUP #
# ================================= #

# Enables POSIX-compliant strict mode
# -e : Exit immediately on simple command fails (caveat of simple commands failing inside of if, while statements of combined with &&/||).
# -u : Unset variables are treated as an error.
# -o pipefail: Changes default exit status of the pipeline from the last command to the rightmost command with a non-zero exit code.
#              Ensures failures upstream are not silent/masked and trigger an exit.
set -e
set -u
# pipefail is not POSIX compliant, check in subshell if pipefail is valid in this environment.
if (set -o ) 2>/dev/null | grep -q pipefail; then
  set -o pipefail
fi

# Resolve script directory using POSIX-compliant method.
# This avoids potential issues with symlinks, relative paths, file names with hyphens and side effects of CDPATH.
PROJ_ROOT=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
if [ -f "${SCRIPT_DIR}/../utils/colors.sh" ]; then
  . "${PROJ_ROOT}/../utils/colors.sh"
else
    # Duplicate fallback from colors.sh incase file is not found.
    # No colors if this is output is being redirected.
    RED=""
    GREEN=""
    YELLOW=""
    BLUE=""
    BOLD=""
    RESET=""
fi

# ASCHII Values for speical handling on input loop.
readonly ETX=$(printf '\003')  # ASCII 3 (Ctrl+C / EO‐Text)
readonly EOT=$(printf '\004')  # ASCII 4 (Ctrl+D / EO-Transmission)
readonly ESC=$(printf '\033')  # ASCII 27 (Escape key)
readonly DEL=$(printf '\177')  # ASCII 127 (Delete / Backspace)
readonly S=$(printf '\010')    # ASCII 8 (Backspace / Ctrl+H)
readonly NL=$(printf '\n')     # ASCII 10 (Line Feed / Newline)
readonly CR=$(printf '\r')     # ASCII 13 (Carriage Return)

# The expected confirmation word + length, note capitalization is required.
readonly EXPECTED="ERASE"
readonly LENGTH=${#EXPECTED}
readonly TARGET_DEVICE="/dev/nvme0n1"

# Terminal settings variable to restore terminal behavior on exit.
SAVED_STTY=""

# Input buffer and position tracking for cursor/typed characters.
typed=""
position=0

# Function to handle cleanup on exit.
cleanup() {
  # Check if SAVED_STTY is set, if so restore terminal settings.
  if [ -n "$SAVED_STTY" ]; then
    stty "$SAVED_STTY" # Restore original behavior
    tput cnorm # Return to visible cursor
  fi
  printf '\n'
}

set_trap() {
  # If the terminal is interactive then set trap (i.e., not piped or redirected).
  if [ -t 0 ]; then
    # Store current terminal settings to later restore.
    # -g : Prints all settings.
    SAVED_STTY=$(stty -g)

    # Set new terminal behavior.
    # -echo : Disable terminal echo.
    # raw : Set character-by-character input (non-line buffered).
    stty -echo raw

    # Hide cursor
    tput civis

    # Pseudo-hook to the cleanup function on termination associated signal events.
    # EXIT : On normal shell exit, only can be sent from inside the shell.
    # INT (SIGINT) : On interupt signal of Ctrl + C.
    # TERM (SIGTERM) : Clean kill/termination, unlike EXIT can come from outside the shell.
    trap cleanup EXIT INT TERM
  else
    # If not in an interactive terminal, set a simple newline trap and empty tty settings.
    trap 'printf "\n"' EXIT INT TERM
    SAVED_STTY=""
  fi
}

# ================================== #
# INPUT CHARACTER HANDLING FUNCTIONS #
# ================================== #

# Checks if arg 1 is a control character associated with an early exit.
is_exit_character() {
  local char="$1"
  [ "$char" = "$ETX" ] || [ "$char" = "$EOT" ] || [ "$char" = "$ESC" ]
}

# Checks if arg 1 is a control character associated with a revert.
is_revert_character() {
    local char="$1"
    [ "$char" = "$DEL" ] || [ "$char" = "$BS" ]
}

# Checks if arg 1 is a control character associated with a confirmation.
is_confirmation_character() {
    local char="$1"
    [ "$char" = "$NL" ] || [ "$char" = "$CR" ]
}

# ================= #
# UTILITY FUNCTIONS #
# ================= #

# Checks if arg 1 is a valid prefix of arg 2 in both length and spelling.
is_valid_prefix() {
    local typed_str="$1"
    local expected_str="$2"
    
    # Check length.
    [ "${#typed_str}" -le "${#expected_str}" ] || return 1
    
    # Check if typed string matches the beginning of expected string.
    [ "${expected_str%${expected_str#${typed_str}}}" = "$typed_str" ]
}

# Removes the last character from the printed string in terminal.
remove_last_character() {
    local input="$1"
    printf '%s' "${input%?}"
}

# ================= #
# DISPLAY FUNCTIONS #
# ================= #

# Displays the confirmation prompt with the expected word.
display_opening_warning() {
  printf '%s%sWARNING:%s Continuing with this script will completely erase all data on /dev/nvme0n1%s\n' \
    "$BOLD" "$RED" "$RESET" "$RESET"
  printf 'Type %s"%s"%s' "$BOLD" "$EXPECTED" "$RESET"
  printf ' to continue and accept...\n'
}

# Displays the input character in green if the character is a valid prefix of the expected string, otherwise red
display_character_with_validation() {
    local char="$1"
    local current_typed="$2"
    local expected_str="$3"
    
    if is_valid_prefix "$current_typed" "$expected_str"; then
        printf '%s%s%s' "$GREEN" "$char" "$RESET"
    else
        printf '%s%s%s' "$RED" "$char" "$RESET"
    fi
}

# Displays the operation cancellation message on early user exit.
display_cancellation() {
    printf '\n%sOperation canceled by user.%s\n' "$YELLOW" "$RESET"
}

# Displays the confirmation message on an exact user input match with the expected string.
display_success() {
    printf '\n%sConfirmation accepted. Proceeding with installation...%s\n' "$GREEN" "$RESET"
}

# Displays the failure message when the supplied input does not match the expected string.
display_failure() {
    printf '\n%sInvalid confirmation. Installation aborted.%s' "$RED" "$RESET"
    printf '\n%sNo system modification have been made and no changes have been written to disk.%s\n' "$RED" "$RESET"
}