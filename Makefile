# Cáptalo build, test and install commands. Run from the repository root.
# Every xcodebuild call pipes through xcbeautify with pipefail.

DEVELOPER_DIR ?= /Applications/Xcode-beta.app/Contents/Developer
export DEVELOPER_DIR
SHELL := /bin/bash

CONFIG ?= Debug
DERIVED := .local/build/DerivedData
LOGS := .local/build/logs
STAMP := $(shell date -u +%Y%m%dT%H%M%SZ)
XCODEBUILD ?= xcodebuild
CORE := Packages/CaptaloCore
TEAM_ARG = $(if $(TEAM),DEVELOPMENT_TEAM=$(TEAM),)
# build-info.json inputs, passed as build settings so the Run Script phase stays sandboxed.
COMMIT := $(shell git rev-parse HEAD 2>/dev/null || echo unknown)
DIRTY := $(shell [ -n "$$(git status --porcelain 2>/dev/null)" ] && echo true || echo false)

# $(call xcb,<log name>,<xcodebuild arguments>)
# Apple's /usr/bin/make (GNU Make 3.81) ignores .SHELLFLAGS, so the recipe sets pipefail itself.
xcb = set -o pipefail; $(XCODEBUILD) -project Captalo.xcodeproj -scheme Captalo -derivedDataPath $(DERIVED) \
	CAPTALO_COMMIT=$(COMMIT) CAPTALO_DIRTY=$(DIRTY) $(2) 2>&1 | tee $(LOGS)/$(1)-$(STAMP).log | xcbeautify --quiet

PROJECT_TEAM = $(shell sed -n 's/.*DEVELOPMENT_TEAM = "*\([A-Z0-9]*\)"*;.*/\1/p' Captalo.xcodeproj/project.pbxproj | head -1)

.PHONY: help xcbeautify-check signing-check build build-unsigned build-unsigned-debug build-unsigned-release \
	test test-core-debug test-core-release script-test log-audit verify install run signing-setup

help:
	@echo "make build [CONFIG=Debug|Release] | build-unsigned | test | log-audit | script-test | verify"
	@echo "make signing-setup [TEAM=<team id>]   one-time Apple Development certificate setup"
	@echo "make install [CONFIG=Debug|Release]    integration owner only: fixed install at /Applications/Captalo.app"

xcbeautify-check:
	@command -v xcbeautify >/dev/null || { echo "Install xcbeautify: brew install xcbeautify"; exit 1; }

signing-check:
	@Scripts/signing-identity >/dev/null

$(LOGS):
	@mkdir -p $(LOGS)

build: xcbeautify-check | $(LOGS)
	$(call xcb,build-$(CONFIG),-configuration $(CONFIG) build $(TEAM_ARG))

build-unsigned: build-unsigned-debug build-unsigned-release

build-unsigned-debug build-unsigned-release: build-unsigned-%: xcbeautify-check | $(LOGS)
	$(call xcb,build-unsigned-$*,-configuration $(if $(filter debug,$*),Debug,Release) CODE_SIGNING_ALLOWED=NO build)

test: test-core-debug test-core-release

test-core-debug:
	swift test --package-path $(CORE)

test-core-release:
	swift test --package-path $(CORE) -c release

script-test:
	python3 -m unittest discover -s Scripts/tests

log-audit:
	Scripts/log-audit Captalo

# The full sequential suite. The step list lives in .rpi/policy.json.
verify:
	python3 .rpi/scripts/rpi-verify.py

# One-time: the first automatic-signing build creates the Apple Development
# certificate for the Personal Team. Needs TEAM, or DEVELOPMENT_TEAM set in the project.
signing-setup: xcbeautify-check | $(LOGS)
	@if [ -z "$(TEAM)$(PROJECT_TEAM)" ]; then \
		echo "No team ID. Open Captalo.xcodeproj in Xcode, select the Captalo target > Signing & Capabilities,"; \
		echo "choose your Personal Team (this writes DEVELOPMENT_TEAM into the project), then run make signing-setup."; \
		echo "Or pass it directly: make signing-setup TEAM=<10-character team ID>."; \
		exit 2; fi
	$(call xcb,signing-setup,-configuration Debug -allowProvisioningUpdates build $(TEAM_ARG))
	Scripts/signing-identity --name

# Identity check, then the same signed build as `make build`, then stage, verify and replace.
install: xcbeautify-check signing-check build
	Scripts/install --config $(CONFIG) --app $(DERIVED)/Build/Products/$(CONFIG)/Captalo.app

run:
	open /Applications/Captalo.app
