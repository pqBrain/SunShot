.DEFAULT_GOAL := help
SHELL := /bin/bash

help: ## Show targets
	@grep -E '^[a-z-]+:.*## ' $(MAKEFILE_LIST) | awk 'BEGIN{FS=":.*## "}{printf "  \033[36m%-18s\033[0m %s\n", $$1, $$2}'

setup: ## One-time: install git hooks
	git config core.hooksPath .githooks
	@echo "hooks installed (.githooks): pre-commit = fast gate, pre-push = full gate"

gate: ## Full quality gate (pre-push)
	@scripts/gate.sh

gate-fast: ## Fast gate (pre-commit): format, hygiene, architecture, build, test
	@scripts/gate.sh --fast

gate-ci: ## CI subset: static checks, builds, Core tests, traceability (no GPU/video)
	@scripts/gate.sh --ci

gate-selftest: ## Prove the gate catches planted defects
	@scripts/gate-selftest.sh

format: ## Auto-format all Swift sources
	swift format format --in-place --recursive --parallel Package.swift Sources Tests

lint: ## Format check + hygiene + architecture
	@scripts/gate.sh format hygiene architecture

build: ## Debug build, warnings as errors
	swift build -Xswiftc -warnings-as-errors

test: ## Unit + snapshot tests
	swift test --parallel -Xswiftc -warnings-as-errors

coverage: ## Tests + per-module coverage thresholds
	@scripts/gate.sh build test coverage

snapshots-record: ## Re-record snapshot references (review the diff before committing!)
	SUNSHOT_RECORD_SNAPSHOTS=1 swift test --filter Snapshot || true
	@git status --short Tests

app: ## Build dist/Sunshot.app (release, ad-hoc signed)
	@scripts/bundle-app.sh

release: ## Package dist/Sunshot-<VERSION>.zip (+ SHA-256) for a GitHub release
	@scripts/package-release.sh

run: app ## Build and open the app
	open dist/Sunshot.app

smoke: app ## Headless smoke test + GUI launch check
	@scripts/smoke-test.sh --launch

monitor: ## Watch the running Sunshot's CPU and memory (every 5 s)
	@scripts/measure-resources.sh --watch

perf: ## Release-mode performance budgets
	@scripts/gate.sh perf

clean: ## Remove build outputs
	rm -rf .build dist

.PHONY: help setup gate gate-fast gate-ci gate-selftest format lint build test coverage snapshots-record app release run smoke monitor perf clean
