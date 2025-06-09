#!/usr/bin/env bash

# File: terminal_lib.sh
# Desc: Terminal library for all common terminal operations including setup/teardown.
# Author: Joseph Mowery
# Email: mowery.joseph@outlook.com

# ========================== #
# INTERNAL LIBRARY VARIABLES #
# ========================== #

# Internal variable to store terminal settings
_TERMINAL_LIB_SAVED_STTY=""

# Flag to track if terminal settings have already been initialized.
# This prevents double initialization to prevent the original terminal settings from being overwritten.
_TERMINAL_LIB_INITIALIZED=false

# ============================= #
# TERMINAL MANAGEMENT FUNCTIONS #
# ============================= #

# Checks if shell is running as an interactive terminal.
# ...Is file descriptor 0 (stdin) connected to this terminal device?
is_interactive_terminal() {
    [ -t 0 ]
}

# Checks if the script is being sourced or executed directly.
prevent_direct_execution() {
  # The return command is only valid in within sourced scripts.
  # If this script is executed directly, it will fail.
  (return 0 2>/dev/null) || {
    echo "This script should not be called directly."
    echo "To use the installation library, please start with start_installation.sh in the project's root directory."
    exit 1
  }
}

# Prepares terminal for interatcive input.
# Saves original stty settings in _TERMINAL_LIB_SAVED_STTY.
setup_interactive_terminal() {
  # Prevent double initialization
  if [ "$_TERMINAL_LIB_INITIALIZED" = true ]; then
      return 0
  fi
    
  # Save current terminal settings first
  _save_terminal_settings || return 1
    
  if is_interactive_terminal; then
    # Set new terminal behavior.
    # -echo : Disable terminal echo.
    # raw : Set character-by-character input (non-line buffered).
    #stty -echo raw 2>/dev/null || return 1

    # Disable canonical input (no line buffering)
    stty -icanon 2>/dev/null || return 1
    # Disable echo (characters won't appear on screen)
    stty -echo 2>/dev/null || return 1
    # Disable signal processing (EX: Ctrl+C becomes regular input)
    stty -isig 2>/dev/null || return 1
    # Set minimum read to 1 character, no timeout
    stty min 1 time 0 2>/dev/null || return 1

    # Hide cursor
    tput civis 2>/dev/null || :
        
    # Set up signal handlers for proper cleanup
    trap _cleanup EXIT INT TERM
  else
    # For non-interactive terminals, just set up a simple newline trap
    trap 'printf "\n"' EXIT INT TERM
  fi

  # Mark as initialized
  _TERMINAL_LIB_INITIALIZED=true

  return 0
}

# Function to handle cleanup on exit.
_cleanup() {
  # Only restore if we have saved settings
  if [ -n "$_TERMINAL_LIB_SAVED_STTY" ]; then
    stty "$_TERMINAL_LIB_SAVED_STTY" 2>/dev/null || :
    tput cnorm 2>/dev/null || :  # Show cursor
  fi
  printf '\n'
}

# Save current terminal settings to restore later.
_save_terminal_settings() {
  if is_interactive_terminal; then
        _TERMINAL_LIB_SAVED_STTY=$(stty -g 2>/dev/null) || :
  else
        _TERMINAL_LIB_SAVED_STTY=""
  fi
}