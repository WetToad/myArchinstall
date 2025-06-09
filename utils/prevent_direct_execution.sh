#!/usr/bin/env bash

# File: prevent_direct_execution.sh
# Desc: Boiler plate function to source at the top of all functional script to ensure they are not called by users/out of order.
# Author: Joseph Mowery
# Email: mowery.joseph@outlook.com

# POSIX-compliant way to detect if script is being sourced or executed
# "Remove the longest match from the beginning of $0 that matches */"
if [ "${0##*/}" = "terminal_lib.sh" ]; then
  echo "This script should not be called directly."
  echo "To use the installation library please start with start_installation.sh in the projects root directory."
  exit 1
fi

# Attempt to return; if it fails, the script is executed directly
(return 0 2>/dev/null) || {
  echo "This script should not be called directly."
  echo "To use the installation library, please start with start_installation.sh in the project's root directory."
  exit 1
}