#!/usr/bin/env bash

# File: confirmation.sh
# Desc: Stylized interactive confirmation prompt to continue with proceeding destructive scripts.
# Author: Joseph Mowery
# Email: mowery.joseph@outlook.com

# Enables strict mode, pipefail is not POSIX compliant so guard against it in executions cases of POSIX compliant environments
# -e : Exit immediately on simple command fails (caveat of simple commands failing inside of if, while statements of combined with &&/||)
# -u : Unset variables are treated as an error
# -o : Changes default exit status of the pipeline from the last command to the rightmost command with a non-zero exit code.
#      Ensures failures upstream are not silent/masked and trigger an exit.
set -e
set -u
if (set -o | grep -q pipefail) 2>/dev/null; then
  set -o pipefail
fi

# Source colors via absolute path resolution
SCRIPT_DIR=$(cd "$(dirname "$0")" && pwd)
if [ -f "${SCRIPT_DIR}/../utils/colors.sh" ]; then
  . "${SCRIPT_DIR}/../utils/colors.sh"
fi

# ASCHII Values to handle on input loop
ETX=$(printf '\003')    # ASCII 3 (Ctrl+C / EO‐Text)
EOT=$(printf '\004')    # ASCII 4 (Ctrl+D / EO-Transmission)
ESC=$(printf '\033')    # ASCII 27 (Escape key)
DEL=$(printf '\177')    # ASCII 127 (Delete / Backspace)
BS=$(printf '\010')     # ASCII 8 (Backspace, often Ctrl+H)
NL=$(printf '\n')       # ASCII 10 (Line Feed / Newline)
CR=$(printf '\r')       # ASCII 13 (Carriage Return)

# The expected confirmation word + length, note capitalization is required
EXPECTED="ERASE"
LENGTH=${#EXPECTED}

# Promp user with warning message and text confirmation
printf '%s%sWARNING:%s Continuing with this script will completely erase all data on /dev/nvme0n1%s\n' \
  "$BOLD" "$RED" "$RESET" "$RESET"
printf 'Type %s"%s"%s' "$BOLD" "$EXPECTED" "$RESET"
printf ' to continue and accept...\n'

# Function to handle cleanup before exit
cleanup() {
  stty "$SAVED_STTY" # Restore original behavior
  tput cnorm # Return to showing cursor
  printf '\n'
}

# Store current terminal settings to later restore
# -g : Prints all settings
SAVED_STTY=$(stty -g)

# Pseudo-hook to the cleanup function on termination associated signal events 
# EXIT : On normal shell exit, only can be sent from inside the shell
# INT (SIGINT) : On interupt signal of Ctrl + C 
# TERM (SIGTERM) : Clean kill/termination, unlike EXIT can come from outside the shell
trap cleanup EXIT INT TERM

# Set new terminal behavior
# -echo : Disable terminal echo
# raw : Set character-by-character input (non-line buffered)
stty -echo raw

# Hide cursor
tput civis

typed=""
position=0

# Main user input loop, works one byte at a time
# “while :” is POSIX‐safe (':' is a shell builtin that does nothing, returns 0)
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
      # The entire typed string matches the beginning of EXPECTED, still must wait for confirmation
      printf '%s%s%s' "$GREEN" "$char" "$RESET"
    else
      # Either too long or does not match the expected prefix
      printf '%s%s%s' "$RED" "$char" "$RESET"
    fi
  fi
done

# Confirmation has been supplied, check if input matches expected
if [ "$typed" = "$EXPECTED" ]; then
  printf '%sConfirmation accepted. Proceeding with installation...%s\n' "$GREEN" "$RESET"
else
  printf '%sInvalid confirmation. Installation aborted.%s\n' "$RED" "$RESET"
  printf '%sNo system modification have been made and no changes been written to disk.%s\n' "$RED" "$RESET"
  exit 1
fi