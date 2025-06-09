#!/usr/bin/env bash

# Generate ANSI escape sequences dynamically using Portable Terminal Control (tput)
if [ -t 1 ]; then # check if stdout(1) is a terminal
    RED=$(tput setaf 1)
    GREEN=$(tput setaf 2)
    YELLOW=$(tput setaf 3)
    BLUE=$(tput setaf 4)
    BOLD=$(tput bold)
    RESET=$(tput sgr0)
else
    # Fallback, no colors if this is output is being redirected
    RED=""
    GREEN=""
    YELLOW=""
    BLUE=""
    BOLD=""
    RESET=""
fi