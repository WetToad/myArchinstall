# File: Makefile
# Desc: Makefile for automating common developement lifecycle tasks.
# Author: Joseph Mowery
# Email: mowery.joseph@outlook.com

# Tell Make these targets are not associated with files.
.PHONY: linuxify-line-endings test check clean

# Makefile pattern rule for linting individual shell scripts
%.lint: %.sh
	@printf "Linting %s...\n" "$<"
	-shellcheck $<
	@touch $@

# Find all shell scripts and create lint targets
SCRIPT_DIRS := libs scripts utils
SHELL_SCRIPTS := $(shell find $(SCRIPT_DIRS) -name "*.sh" -type f 2>/dev/null)
LINT_TARGETS := $(SHELL_SCRIPTS:.sh=.lint)

# Development in WSL2 will have Windows line endings in .shellcheckrc, converts CRLF to LF to avoid errors.
linuxify-line-endings:
	@tr -d '\r' < .shellcheckrc > .shellcheckrc.fixed
	@mv .shellcheckrc.fixed .shellcheckrc

# Static analysis on scripts for POSIX compliance via Shellcheck, uses .shellcheckrc config in root directory.
lint: $(LINT_TARGETS)
	@printf "Running Shellcheck linter...\n"

# Dynamic analysis via Shellspec test suite, uses .shellspec config in root directory.
test: $(SHELL_SCRIPTS)
	@printf "Running Shellspec test suite...\n"
	shellspec

# Clean up marker files
clean:
	rm -f $(LINT_TARGETS)

check: linuxify-line-endings lint test