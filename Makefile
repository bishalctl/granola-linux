.DEFAULT_GOAL := help

SCRIPT := ./granola-linux
DRY := $(if $(DRY_RUN),--dry-run,)

.PHONY: help check lint install uninstall status

help: ## Show the targets
	@awk 'BEGIN { FS = ":.*## " } /^[a-z-]+:.*## / { printf "  %-10s %s\n", $$1, $$2 }' $(MAKEFILE_LIST)
	@echo
	@echo "  DRY_RUN=1 on install or uninstall prints what would happen and changes nothing."
	@echo "  DMG=path on install uses a disk image you already have."

check: lint ## Run every check
	$(SCRIPT) check-runtime

lint: ## Check the script's syntax and run shellcheck
	bash -n $(SCRIPT)
	shellcheck -S style $(SCRIPT)
	sh -n .github/scripts/check-commits.sh

install: ## Download the current Granola release and install it
	$(SCRIPT) install $(DRY) $(if $(DMG),--dmg $(DMG),)

uninstall: ## Remove the install (keeps Granola's user data)
	$(SCRIPT) uninstall $(DRY)

status: ## Show the installed version and the current release
	$(SCRIPT) status
