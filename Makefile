SHELL := /bin/bash

.DEFAULT_GOAL := help

.PHONY: help doctor bootstrap resolve build universal run test strict check acceptance lifecycle package install uninstall

help: ## Show the contributor commands
	@awk 'BEGIN {FS = ":.*## "; printf "CornerFloat contributor commands:\n\n"} /^[a-zA-Z_-]+:.*## / {printf "  %-12s %s\n", $$1, $$2}' $(MAKEFILE_LIST)

doctor: ## Check the local macOS development environment
	@./scripts/doctor.sh

bootstrap: ## Check the machine and resolve pinned Swift dependencies
	@./scripts/bootstrap.sh

resolve: ## Resolve the pinned Swift dependencies
	@./scripts/swiftpm.sh resolve

build: ## Build an ad-hoc signed app in dist/
	@./scripts/build.sh

universal: ## Build an ad-hoc Universal 2 app for arm64 and x86_64
	@UNIVERSAL=1 ./scripts/build.sh

run: ## Build and open the local app without an Apple developer account
	@./scripts/run.sh

test: ## Run the reproducible contributor test suite
	@./scripts/test.sh

strict: ## Compile with complete Swift concurrency checks and warnings as errors
	@./scripts/strict-concurrency-check.sh

check: doctor test strict ## Run the checks expected before a pull request

acceptance: ## Run AppKit acceptance checks from a logged-in desktop
	@./scripts/acceptance-tests.sh

lifecycle: ## Run window lifecycle and idle-energy diagnostics
	@./scripts/lifecycle-diagnostics.sh

package: ## Create a local, ad-hoc signed DMG
	@./scripts/package-dmg.sh

install: build ## Install the local build in ~/Applications without sudo
	@./scripts/install.sh

uninstall: ## Remove the installed app but preserve preferences and website data
	@./scripts/uninstall.sh
