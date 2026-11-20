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
SPEECH := Packages/CaptaloSpeech
RELEASE_MODELS := $(DERIVED)/Build/Products/Release/Captalo.app/Contents/Resources/Models
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
	test test-core-debug test-core-release script-test log-audit verify install run signing-setup \
	clipboard-sentinel capture-pdf vendor fetch-models update-model-manifest bundle-check offline-test \
	completeness-test test-speech-debug test-speech-release prepare shell-audit defaults-backup defaults-restore ocr-probe \
	panel-render

help:
	@echo "make build [CONFIG=Debug|Release] | build-unsigned | test | log-audit | script-test | verify"
	@echo "make fetch-models | bundle-check | offline-test | completeness-test | ocr-probe | panel-render | update-model-manifest [VOICES=a,b]"
	@echo "make signing-setup [TEAM=<team id>]   one-time Apple Development certificate setup"
	@echo "make install [CONFIG=Debug|Release]    integration owner only: fixed install at /Applications/Captalo.app"

xcbeautify-check:
	@command -v xcbeautify >/dev/null || { echo "Install xcbeautify: brew install xcbeautify"; exit 1; }

signing-check:
	@Scripts/signing-identity >/dev/null

$(LOGS):
	@mkdir -p $(LOGS)

# The pinned, patched FluidAudio and the verified voice files every app build
# needs. The stamp skips the probe build and the 95 MB check while the
# manifest and the patch are unchanged; make fetch-models always rechecks.
PREPARED := .local/build/prepared.stamp
prepare: $(PREPARED)

$(PREPARED): Models.manifest.json Patches/fluidaudio-v0.18.3-xcode27.patch Patches/fluidaudio-v0.18.3-xcode27.commit
	Scripts/prepare-fluidaudio
	Scripts/fetch-models
	@mkdir -p $(dir $@) && touch $@

vendor:
	Scripts/prepare-fluidaudio

fetch-models: vendor
	Scripts/fetch-models

update-model-manifest: vendor
	Scripts/update-model-manifest $(VOICES)

build: xcbeautify-check prepare | $(LOGS)
	$(call xcb,build-$(CONFIG),-configuration $(CONFIG) build $(TEAM_ARG))

build-unsigned: build-unsigned-debug build-unsigned-release

build-unsigned-debug build-unsigned-release: build-unsigned-%: xcbeautify-check prepare | $(LOGS)
	$(call xcb,build-unsigned-$*,-configuration $(if $(filter debug,$*),Debug,Release) CODE_SIGNING_ALLOWED=NO build)

test: test-core-debug test-core-release

test-core-debug:
	swift test --package-path $(CORE)

test-core-release:
	swift test --package-path $(CORE) -c release

# The contract tests read the verified voice files in .local/models.
test-speech-debug: prepare
	swift test --package-path $(SPEECH)

test-speech-release: prepare
	swift test --package-path $(SPEECH) -c release

bundle-check: vendor
	Scripts/bundle-check

offline-test: vendor
	Scripts/offline-test --probe "$$(Scripts/model-tool)" --bundle $(RELEASE_MODELS)

completeness-test: vendor
	Scripts/completeness-test $(RELEASE_MODELS)

shell-audit:
	Scripts/shell-audit

# The menu-bar panel drawn from fixtures, dark and light (monochrome popover
# plan): the Debug app writes the PNGs, the check counts and measures them.
# View them in .local/build/panel-render before a signed install.
PANEL_RENDER := .local/build/panel-render
panel-render: build-unsigned-debug
	mkdir -p $(PANEL_RENDER) && rm -f $(PANEL_RENDER)/*.png
	$(DERIVED)/Build/Products/Debug/Captalo.app/Contents/MacOS/Captalo --render-panel "$(CURDIR)/$(PANEL_RENDER)"
	Scripts/panel-render-check $(PANEL_RENDER)

# Region OCR (phase 5): Release-built Vision probe on the synthetic fixtures, plus one cancel.
ocr-probe:
	Scripts/ocr-probe

# Fresh-state check on the fixed identity (phase 4, manual). Touches only the
# com.thecreativetoken.captalo defaults domain; quit Cáptalo first.
defaults-backup:
	Scripts/defaults-backup

defaults-restore:
	Scripts/defaults-restore

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

# Capture matrix helpers (plan phase 2). clipboard-sentinel REPLACES the general clipboard.
clipboard-sentinel:
	xcrun swift Scripts/clipboard-sentinel.swift

capture-pdf:
	@mkdir -p .local/fixtures
	cupsfilter Fixtures/capture-matrix.txt > .local/fixtures/capture-matrix.pdf 2>/dev/null
	@echo ".local/fixtures/capture-matrix.pdf"
