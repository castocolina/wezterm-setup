# wezterm-setup — thin glue. Each target is at most five lines including its banner.
# Anything longer dispatches into tools/ or a wez subcommand.
# See docs/agent-iteration.md (R3 — config layer is composable).

.DEFAULT_GOAL := help
.PHONY: help setup install build publish clean doctor test uninstall

help:
	@echo "wezterm-setup targets:"
	@echo "  setup                    install the sudo-free dev compile toolchain (lua@5.4 + luastatic)"
	@echo "  install                  inject sentinel block into wezterm.lua + install wez CLI"
	@echo "  build                    build dist/wez (luastatic single binary, same path CI uses)"
	@echo "  publish                  build + upload this platform's wez-<os>-<arch> asset to the release"
	@echo "  clean                    wipe .tmp/ scratch; keep install intact"
	@echo "  doctor                   diagnose install state and config health"
	@echo "  test                     run test suite (set WEZTERM_INTEGRATION=1 for live tests)"
	@echo "  uninstall                remove config block, wez CLI, and backups"
	@echo "  uninstall KEEP_CONFIG=1  preserve ~/.config/wezterm/wezterm-setup/; remove CLI only"
	@echo "  uninstall KEEP_CLI=1     preserve wez binary; remove config block"
	@echo "  uninstall KEEP_BACKUP=1  preserve wezterm.lua.bak.*; remove the rest"

setup:
	@./tools/setup-dev.sh

install:
	@./tools/setup.sh

build:
	@./tools/build.sh

publish:
	@./tools/publish.sh

clean:
	@rm -rf .tmp/

doctor:
	@wez doctor

test:
	@./tools/run-tests.sh

uninstall:
	@KEEP_CONFIG="$(KEEP_CONFIG)" KEEP_CLI="$(KEEP_CLI)" KEEP_BACKUP="$(KEEP_BACKUP)" ./tools/uninstall.sh
