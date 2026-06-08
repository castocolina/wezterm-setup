# wezterm-setup — thin glue. Each target is at most five lines including its banner.
# Anything longer dispatches into tools/ or a wez subcommand.
# See docs/agent-iteration.md (R3 — config layer is composable).

.DEFAULT_GOAL := help
.PHONY: help install clean doctor test uninstall

help:
	@echo "wezterm-setup targets:"
	@echo "  install                  inject sentinel block into wezterm.lua + install wez CLI"
	@echo "  clean                    wipe .tmp/ scratch; keep install intact"
	@echo "  doctor                   diagnose install state and config health"
	@echo "  test                     run test suite (set WEZTERM_INTEGRATION=1 for live tests)"
	@echo "  uninstall                remove config block, wez CLI, and backups"
	@echo "  uninstall KEEP_CONFIG=1  preserve ~/.config/wezterm/wezterm-setup/; remove CLI only"
	@echo "  uninstall KEEP_CLI=1     preserve wez binary; remove config block"
	@echo "  uninstall KEEP_BACKUP=1  preserve wezterm.lua.bak.*; remove the rest"

install:
	@./tools/setup.sh

clean:
	@rm -rf .tmp/

doctor:
	@wez doctor

test:
	@./tools/run-tests.sh

uninstall:
	@KEEP_CONFIG="$(KEEP_CONFIG)" KEEP_CLI="$(KEEP_CLI)" KEEP_BACKUP="$(KEEP_BACKUP)" ./tools/uninstall.sh
