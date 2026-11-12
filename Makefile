# KBPulse — build interface.
#
# `make` prints the list of targets. Every target is phony.

SHELL := /bin/bash

APP_NAME    := KBPulse
PROJECT     := KBPulse.xcodeproj
SCHEME      ?= kbpulse
TEST_SCHEME := KBPulseAppTests
CONFIGURATION ?= Release
BUILD_DIR   := build
APP_BUNDLE  := $(BUILD_DIR)/$(APP_NAME).app
RELEASE_DIR := release
INSTALL_DIR ?= $(HOME)/Applications
INSTALL_APP := $(INSTALL_DIR)/$(APP_NAME).app
# The remote the release is cut from. The upstream checkout uses origin; a fork
# checkout passes REMOTE=fork so the push commands name the fork.
REMOTE ?= origin

# The version comes from the command line: `make release VERSION=1.2.3`.
# A local build without it keeps MARKETING_VERSION from the Xcode project.
VERSION ?=
BUILD_NUMBER ?= $(shell git rev-list --count HEAD 2>/dev/null || echo 1)

.PHONY: help build test verify app install run dmg release-artifacts \
	release-notes release clean _require_version

.DEFAULT_GOAL := help

## help — list every target

help:
	@printf '%s\n' \
		'KBPulse — build targets.' \
		'' \
		'  help                 List every target (default).' \
		'  build                Build the app and the embedded CLI with xcodebuild.' \
		'  test                 Run the changelog check and the Xcode test suite.' \
		'  verify               Check the bundle, the embedded CLI, the version and the signature.' \
		'  app                  Build the ad-hoc signed bundle into build/KBPulse.app.' \
		'  install              Copy the bundle into ~/Applications.' \
		'  run                  Install the bundle and launch it.' \
		'  dmg                  Build the disk image build/KBPulse.dmg.' \
		'  release-artifacts    Build release/KBPulse-<version>.dmg and its verified checksum.' \
		'  release-notes VERSION=x.y.z  Print the changelog section of a version.' \
		'  release VERSION=x.y.z  Bump the changelog, test, build, verify, commit and tag.' \
		'  clean                Remove build/ and release/.' \
		'' \
		'Notes' \
		'  The app and the embedded kbpulse CLI come from the Xcode project. The' \
		'  Makefile wraps build-dmg.sh, which builds the app, signs it ad-hoc and' \
		'  packages the DMG.' \
		'  CHANGELOG.md follows the shared shape and `make test` checks it.' \
		'  `make release` moves [Unreleased] to the version, runs the tests, builds' \
		'  and verifies the artifacts, commits the bump and creates the annotated tag.' \
		'  It prints the push commands and never pushes.' \
		'  The release is cut from REMOTE (default origin). In a fork checkout use' \
		'  `make release VERSION=1.2.3 REMOTE=fork` so the push commands name the' \
		'  fork that publishes the release.'

## build — build the app and the embedded CLI

build:
	xcodebuild -project "$(PROJECT)" -scheme "$(SCHEME)" \
		-configuration "$(CONFIGURATION)" \
		-derivedDataPath "$(BUILD_DIR)/DerivedData" \
		CODE_SIGNING_ALLOWED=NO build

## test — the changelog check and the Xcode suite

test:
	./scripts/changelog.sh check
	xcodebuild test -project "$(PROJECT)" -scheme "$(TEST_SCHEME)" \
		-destination 'platform=macOS' \
		-derivedDataPath "$(BUILD_DIR)/TestDerivedData" \
		CODE_SIGNING_ALLOWED=NO

## app — the signed bundle

app:
	MARKETING_VERSION="$(VERSION)" CURRENT_PROJECT_VERSION="$(BUILD_NUMBER)" \
		./build-dmg.sh app "$(CONFIGURATION)"

## verify — check the built bundle

verify:
	@test -d "$(APP_BUNDLE)" || { \
		echo "error: $(APP_BUNDLE) is missing. Run make app first."; \
		exit 1; \
	}
	@test -x "$(APP_BUNDLE)/Contents/Helpers/kbpulse" || { \
		echo "error: the kbpulse CLI is not embedded in $(APP_BUNDLE)."; \
		exit 1; \
	}
	@if [ -n "$(strip $(VERSION))" ]; then \
		version="$$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' "$(APP_BUNDLE)/Contents/Info.plist")"; \
		echo "Bundle version: $$version (expected $(VERSION))"; \
		test "$$version" = "$(VERSION)" || { \
			echo "error: the bundle reports $$version, but $(VERSION) was expected."; \
			exit 1; \
		}; \
	else \
		echo "Bundle version: $$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' "$(APP_BUNDLE)/Contents/Info.plist") (no VERSION given)"; \
	fi
	codesign --verify --deep --strict "$(APP_BUNDLE)"
	@echo "Verified $(APP_BUNDLE)."

## install — copy the bundle into ~/Applications

install: app
	@mkdir -p "$(INSTALL_DIR)"
	@rm -rf "$(INSTALL_APP)"
	ditto "$(APP_BUNDLE)" "$(INSTALL_APP)"
	@echo "Installed $(INSTALL_APP)"

## run — install the bundle and launch it

run: install
	open "$(INSTALL_APP)"

## dmg — the disk image

dmg:
	MARKETING_VERSION="$(VERSION)" CURRENT_PROJECT_VERSION="$(BUILD_NUMBER)" \
		./build-dmg.sh dmg "$(CONFIGURATION)"

## release-artifacts — the versioned DMG and its checksum

release-artifacts: _require_version dmg
	@mkdir -p "$(RELEASE_DIR)"
	cp "$(BUILD_DIR)/$(APP_NAME).dmg" "$(RELEASE_DIR)/$(APP_NAME)-$(VERSION).dmg"
	@cd "$(RELEASE_DIR)" && shasum -a 256 "$(APP_NAME)-$(VERSION).dmg" > "$(APP_NAME)-$(VERSION).dmg.sha256"
	@cd "$(RELEASE_DIR)" && shasum -a 256 -c "$(APP_NAME)-$(VERSION).dmg.sha256"
	@echo "$(RELEASE_DIR)/$(APP_NAME)-$(VERSION).dmg.sha256:"
	@cat "$(RELEASE_DIR)/$(APP_NAME)-$(VERSION).dmg.sha256"

## release-notes — print the changelog section of a version

release-notes:
	@if [ -z "$(strip $(VERSION))" ]; then \
		echo "error: make release-notes needs a version, for example: make release-notes VERSION=1.2.3"; \
		exit 1; \
	fi
	@./scripts/changelog.sh notes "$(VERSION)"

## release — bump, test, build, verify, commit and tag, without pushing

release:
	@if [ -z "$(strip $(VERSION))" ]; then \
		echo "error: make release needs a version, for example: make release VERSION=1.2.3"; \
		exit 1; \
	fi
	@APP_NAME="$(APP_NAME)" REMOTE="$(REMOTE)" ./scripts/release.sh "$(VERSION)"

## clean — remove the build output

clean:
	rm -rf "$(BUILD_DIR)" "$(RELEASE_DIR)"
	@echo "Removed $(BUILD_DIR)/ and $(RELEASE_DIR)/."

_require_version:
	@if [ -z "$(strip $(VERSION))" ]; then \
		echo "error: $(MAKECMDGOALS) needs a version, for example: make $(MAKECMDGOALS) VERSION=1.2.3"; \
		exit 1; \
	fi
