# spec/spec_helper.sh

# Override 'stty' so it’s a no-op:
stty() { :; }

# Override 'tput' so it’s a no-op:
tput() { :; }

# Provide default color vars (so "$RED" etc. aren’t empty/unset)
BOLD=""
RED=""
GREEN=""
YELLOW=""
RESET=""