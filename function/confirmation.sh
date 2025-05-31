#!/usr/bin/env bash

# File: confirmation.sh
# Desc: Stylized interactive confirmation prompt to continue with proceeding destructive scripts.
# Author: Joseph Mowery
# Email: mowery.joseph@outlook.com

# Enables strict mode
# -e : Exit immediately on simple command fails (caveat of simple commands failing inside of if, while statements of combined with &&/||)
# -u : Unset variables are treated as an error
# -o : Changes default exit status of the pipeline from the last command to the rightmost command with a non-zero exit code.
#      Ensures failures upstream are not silent/masked and trigger an exit.
set -euo pipefail

# Source colors via absolute path resolution
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${SCRIPT_DIR}/../utils/colors.sh"

# The expected confirmation word + length, note capitalization is required
EXPECTED="ERASE"
LENGTH=${#EXPECTED}

# Promp user with warning message and text confirmation
echo "${BOLD}${RED}WARNING: Continuing with this script will completely erase all data on /dev/nvme0n1${RESET}"
echo "Type '${BOLD}${EXPECTED}${RESET}' to continue and accept..."

# Function to handle cleanup before exit
cleanup() {
  stty "$SAVED_STTY" # Restore original behavior
  tput cnorm # Return to showing cursor
  echo
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
while true; do
  # Utilize dd to read in a single character
  # bs=1 : Set block size to 1 byte for 1 char
  # count=1 : 1 block to be read at a time
  # 2>/dev/null : Redirect stderr to /dev/null
  char=$(dd bs=1 count=1 2>/dev/null)
  
  # Check for early exits
  # $'\003' : ASCII code for Ctrl+C (ETX)
  # $'\004' : ASCII code for Ctrl+D (EOF)
  # $'\033' : ASCII code for ESC key
  if [[ "$char" == $'\003' ]] || [[ "$char" == $'\004' ]] || [[ "$char" == $'\033' ]]; then
    echo -e "\n${YELLOW}Operation canceled by user${RESET}"
    exit 1
  # Check for reverts
  # $'\177' : ASCII code for Backspace (BS)
  # $'\010' : ASCII code for Delete (DEL)
  elif [[ "$char" == $'\177' ]] || [[ "$char" == $'\010' ]]; then
    # Is there more than 0 chars in the buffer before doing buffer manipulation
    if [[ ${#typed} -gt 0 ]]; then
      # Remove exactly 1 char from the end of buffer and decrement position
      typed="${typed%?}"
      position=$((position - 1))

      # Erase the last character in the terminal and move cursor backwards
      # -n : Prevents newline
      # -e : Enable interpretation of backslash-escape sequences like \b, \r and \n 
      echo -ne "\b \b"
    fi
  elif [[ "$char" == $'\n' ]] || [[ "$char" == $'\r' ]]; then # Enter key
    echo
    break
  else
    # Concatanate typed char to internal buffer, increment position
    typed="${typed}${char}"
    position=$((position + 1))
    
    # Check if current typed string is a valid prefix of EXPECTED
    # This prevents the bug where wrong characters followed by correct ones show green
    if [[ ${#typed} -le ${LENGTH} ]] && [[ "${EXPECTED:0:${#typed}}" == "$typed" ]]; then
      # The entire typed string matches the beginning of EXPECTED
      echo -ne "${GREEN}${char}${RESET}"
    else
      # Either too long or doesn't match the expected prefix
      echo -ne "${RED}${char}${RESET}"
    fi
  fi
done

# Check if input matches exactly
if [[ "$typed" == "$EXPECTED" ]]; then
  echo "${GREEN}Confirmation accepted. Proceeding with erase operation...${RESET}"
  # Add your actual erase command here, e.g.:
  # dd if=/dev/zero of=/dev/nvme0n1 bs=1M status=progress
  echo "This is where the actual erase operation would run."
else
  echo "${RED}Invalid confirmation. Operation aborted.${RESET}"
  exit 1
fi