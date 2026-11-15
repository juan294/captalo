# Cáptalo build, test and install commands. Run from the repository root.
# Every xcodebuild call pipes through xcbeautify with pipefail.

DEVELOPER_DIR ?= /Applications/Xcode-beta.app/Contents/Developer
export DEVELOPER_DIR
SHELL := /bin/bash
# Apple's /usr/bin/make (GNU Make 3.81) ignores .SHELLFLAGS, so every piped
# recipe starts with `set -o pipefail;` itself.
PIPEFAIL := set -o pipefail;

CONFIG ?= Debug
DERIVED := .local/build/DerivedData
LOGS := .local/build/logs
STAMP = $(shell date -u +%Y%m%dT%H%M%SZ)
XCODEBUILD ?= xcodebuild
XCODEBUILD_ARGS := -project Captalo.xcodeproj -scheme Captalo -derivedDataPath $(DERIVED)
TEAM_ARG = $(if $(TEAM),DEVELOPMENT_TEAM=$(TEAM),)
CORE := Packages/CaptaloCore

.PHONY: help xcbeautify-check build build-unsigned build-unsigned-debug build-unsigned-release \
	test test-core-debug test-core-release script-test log-audit verify install run signing-setup

help:
	@echo "make build | build-unsigned | test | log-audit | script-test | verify"
	@echo "make signing-setup [TEAM=<team id>]   one-time Apple Development certificate setup"
	@echo "make install [CONFIG=Debug|Release]    integration owner only: fixed install at /Applications/Captalo.app"

xcbeautify-check:
	@command -v xcbeautify >/dev/null || { echo "Install xcbeautify: brew install xcbeautify"; exit 1; }

$(LOGS):
	@mkdir -p $(LOGS)

build: xcbeautify-check | $(LOGS)
	$(PIPEFAIL) $(XCODEBUILD) $(XCODEBUILD_ARGS) -configuration Debug build $(TEAM_ARG) 2>&1 | tee $(LOGS)/build-Debug-$(STAMP).log | xcbeautify --quiet

build-unsigned: build-unsigned-debug build-unsigned-release

build-unsigned-debug build-unsigned-release: build-unsigned-%: xcbeautify-check | $(LOGS)
	$(PIPEFAIL) $(XCODEBUILD) $(XCODEBUILD_ARGS) -configuration $(if $(filter debug,$*),Debug,Release) CODE_SIGNING_ALLOWED=NO build 2>&1 \
		| tee $(LOGS)/build-unsigned-$*-$(STAMP).log | xcbeautify --quiet

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
PROJECT_TEAM = $(shell sed -n 's/.*DEVELOPMENT_TEAM = "*\([A-Z0-9]*\)"*;.*/\1/p' Captalo.xcodeproj/project.pbxproj | head -1)

signing-setup: xcbeautify-check | $(LOGS)
	@if [ -z "$(TEAM)$(PROJECT_TEAM)" ]; then \
		echo "No team ID. Open Captalo.xcodeproj in Xcode, select the Captalo target > Signing & Capabilities,"; \
		echo "choose your Personal Team (this writes DEVELOPMENT_TEAM into the project), then run make signing-setup."; \
		echo "Or pass it directly: make signing-setup TEAM=<10-character team ID>."; \
		exit 2; fi
	$(PIPEFAIL) $(XCODEBUILD) $(XCODEBUILD_ARGS) -configuration Debug -allowProvisioningUpdates build $(TEAM_ARG) 2>&1 \
		| tee $(LOGS)/signing-setup-$(STAMP).log | xcbeautify --quiet
	Scripts/signing-identity --name

install: xcbeautify-check
	Scripts/install --config $(CONFIG) $(if $(TEAM),--team $(TEAM),)

run:
	open /Applications/Captalo.app
