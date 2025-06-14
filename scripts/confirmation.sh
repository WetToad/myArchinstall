#!/usr/bin/env bash

# File: confirmation.sh
# Desc: Stylized interactive confirmation prompt to continue with proceeding destructive scripts.
# Author: Joseph Mowery
# Email: mowery.joseph@outlook.com

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
SCRIPT_DIR=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
if [ -f "${SCRIPT_DIR}/../utils/colors.sh" ]; then
  . "${SCRIPT_DIR}/../utils/colors.sh"
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

# Prompt user with warning message and text confirmation.
printf '%s%sWARNING:%s Continuing with this script will completely erase all data on /dev/nvme0n1%s\n' \
  "$BOLD" "$RED" "$RESET" "$RESET"
printf 'Type %s"%s"%s' "$BOLD" "$EXPECTED" "$RESET"
printf ' to continue and accept...\n'

# Function to handle cleanup on exit.
cleanup() {
  # Check if SAVED_STTY is set, if so restore terminal settings.
  if [ -n "$SAVED_STTY" ]; then
    stty "$SAVED_STTY" # Restore original behavior
    tput cnorm # Return to visible cursor
  fi
  printf '\n'
}

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

typed=""
position=0

# Main user input loop, works one byte at a time
# “while :;” is POSIX‐safe (':' is a shell builtin that does nothing, returns 0)
while :; do
  # Utilize dd to read in a single character
  # bs=1 : Set block size to 1 byte for 1 char
  # count=1 : 1 block to be read at a time
  # 2>/dev/null : Redirect stderr to /dev/null
  char=$(dd bs=1 count=1 2>/dev/null)
  
  # Check for early exits
  # '\003' : ASCII code for Ctrl+C (ETX)
  # '\004' : ASCII code for Ctrl+D (EOF)
  # '\033' : ASCII code for ESC key
  if [ "$char" = "$ETX" ] || [ "$char" = "$EOT" ] || [ "$char" = "$ESC" ]; then
    printf '\n%sOperation canceled by user.%s\n' "$YELLOW" "$RESET"
    exit 1
  # Check for reverts
  # '\177' : ASCII code for Backspace (BS)
  # '\010' : ASCII code for Delete (DEL)
  elif [ "$char" = "$DEL" ] || [ "$char" = "$BS" ]; then
    # Check if there is more than 0 chars in the buffer before doing buffer manipulation
    if [ "${#typed}" -gt 0 ]; then
      # Remove exactly 1 char from the end of buffer and decrement position
      typed="${typed%?}"
      position=$((position - 1))

      # Erase the last character on the terminal:
      # '\b' : moves back one column
      # ' ' : overwrites the character under the cursor with a space
      # '\b' : moves back again so the cursor is in the erased spot
      printf '\b \b'
    fi
  # Check for confirmation
  # '\n' : Newline
  # '\r' : Carriage return
  elif [ "$char" = "$NL" ] || [ "$char" = "$CR" ]; then
    printf '\n'
    break
  else
    # Concatanate typed char to internal buffer, increment position
    typed="${typed}${char}"
    position=$((position + 1))
    
    # Check if current typed string is a valid prefix of EXPECTED in both length and spelling
    if [ "${#typed}" -le "${LENGTH}" ] && [ "${EXPECTED%${EXPECTED#${typed}}}" = "$typed" ]; then
      # The entire typed string is a subset of EXPECTED, print out char to terminal
      printf '%s%s%s' "$GREEN" "$char" "$RESET"
    else
      # Either too long or does not match the expected prefix
      printf '%s%s%s' "$RED" "$char" "$RESET"
    fi
  fi
done

# Revert back to sane stty settings for printing out if in interactive terminal
[ -t 0 ] && stty sane

# Confirmation has been supplied, check if input matches expected
if [ "$typed" = "$EXPECTED" ]; then
  printf '\n%sConfirmation accepted. Proceeding with installation...%s\n' "$GREEN" "$RESET"
  exit 0
else
  printf '\n%sInvalid confirmation. Installation aborted.%s' "$RED" "$RESET"
  printf '\n%sNo system modification have been made and no changes have been written to disk.%s\n' "$RED" "$RESET"
  exit 1
fi