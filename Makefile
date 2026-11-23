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
ARCH_ARM    := arm64
ARCH_INTEL  := x86_64
APP_ARM     := $(BUILD_DIR)/$(APP_NAME)-$(ARCH_ARM).app
APP_INTEL   := $(BUILD_DIR)/$(APP_NAME)-$(ARCH_INTEL).app
DMG_ARM     := $(BUILD_DIR)/$(APP_NAME)-$(ARCH_ARM).dmg
DMG_INTEL   := $(BUILD_DIR)/$(APP_NAME)-$(ARCH_INTEL).dmg
# The bundles that verify checks. Narrow it for one slice with
# BUNDLES=build/KBPulse-arm64.app on the command line.
BUNDLES     ?= $(APP_ARM) $(APP_INTEL)
HOST_ARCH   := $(shell uname -m)
RELEASE_DIR := release
INSTALL_DIR ?= /Applications
INSTALL_APP := $(INSTALL_DIR)/$(APP_NAME).app

# install and run touch the slice of the machine that runs them.
ifeq ($(HOST_ARCH),$(ARCH_ARM))
HOST_BUNDLE     := $(APP_ARM)
HOST_APP_TARGET := app-arm
else ifeq ($(HOST_ARCH),$(ARCH_INTEL))
HOST_BUNDLE     := $(APP_INTEL)
HOST_APP_TARGET := app-intel
endif

# The remote the release is cut from. The upstream checkout uses origin; a fork
# checkout passes REMOTE=fork so the push commands name the fork.
REMOTE ?= origin

# The version comes from the command line: `make release VERSION=1.2.3`.
# A local build without it keeps MARKETING_VERSION from the Xcode project.
VERSION ?=
BUILD_NUMBER ?= $(shell git rev-list --count HEAD 2>/dev/null || echo 1)

.PHONY: help build test verify app app-arm app-intel install run \
	dmg dmg-arm dmg-intel release-artifacts release-notes release clean \
	_require_version

.DEFAULT_GOAL := help

## help — list every target

help:
	@printf '%s\n' \
		'KBPulse — build targets.' \
		'' \
		'  help                 List every target (default).' \
		'  build                Build the app and the embedded CLI with xcodebuild.' \
		'  test                 Run the changelog check and the Xcode test suite.' \
		'  verify               Check both bundles, the embedded CLI, the architecture,' \
		'                       the version and the signature.' \
		'  app                  Build both ad-hoc signed bundles into build/: KBPulse-arm64.app' \
		'                       and KBPulse-x86_64.app.' \
		'  app-arm              Build the Apple silicon bundle only.' \
		'  app-intel            Build the Intel bundle only.' \
		'  install              Copy the bundle of this machine into /Applications.' \
		'  run                  Install the bundle and launch it.' \
		'  dmg                  Build build/KBPulse-arm64.dmg and build/KBPulse-x86_64.dmg.' \
		'  dmg-arm              Build the Apple silicon disk image only.' \
		'  dmg-intel            Build the Intel disk image only.' \
		'  release-artifacts    Build release/KBPulse-<version>-arm64.dmg,' \
		'                       release/KBPulse-<version>-x86_64.dmg and release/checksums.txt.' \
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
	@if pgrep -x "$(APP_NAME)" >/dev/null; then \
		echo "error: quit $(APP_NAME) before running tests; the test host uses the same bundle identifier."; \
		exit 1; \
	fi
	./scripts/changelog.sh check
	xcodebuild test -project "$(PROJECT)" -scheme "$(TEST_SCHEME)" \
		-destination 'platform=macOS' \
		-derivedDataPath "$(BUILD_DIR)/TestDerivedData" \
		CODE_SIGNING_ALLOWED=NO

## app — both signed bundles

app: app-arm app-intel

## app-arm — the Apple silicon bundle

app-arm:
	MARKETING_VERSION="$(VERSION)" CURRENT_PROJECT_VERSION="$(BUILD_NUMBER)" \
		./build-dmg.sh app $(ARCH_ARM) "$(CONFIGURATION)"

## app-intel — the Intel bundle

app-intel:
	MARKETING_VERSION="$(VERSION)" CURRENT_PROJECT_VERSION="$(BUILD_NUMBER)" \
		./build-dmg.sh app $(ARCH_INTEL) "$(CONFIGURATION)"

## verify — check the built bundles

verify:
	@set -e; \
	for bundle in $(BUNDLES); do \
		test -d "$$bundle" || { \
			echo "error: $$bundle is missing. Run make app first."; \
			exit 1; \
		}; \
		test -x "$$bundle/Contents/Helpers/kbpulse" || { \
			echo "error: the kbpulse CLI is not embedded in $$bundle."; \
			exit 1; \
		}; \
		case "$$bundle" in \
			*$(ARCH_ARM).app) arch=$(ARCH_ARM) ;; \
			*$(ARCH_INTEL).app) arch=$(ARCH_INTEL) ;; \
			*) \
				echo "error: the name of $$bundle does not carry the architecture."; \
				exit 1; \
				;; \
		esac; \
		echo "Bundle: $$bundle ($$arch)"; \
		for binary in "$$bundle/Contents/MacOS/$(APP_NAME)" "$$bundle/Contents/Helpers/kbpulse"; do \
			archs="$$(lipo -archs "$$binary")"; \
			test "$$archs" = "$$arch" || { \
				echo "error: $$binary carries $$archs, but $$arch was expected."; \
				exit 1; \
			}; \
			echo "Architecture: $$archs in $$binary"; \
		done; \
		if [ -n "$(strip $(VERSION))" ]; then \
			version="$$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' "$$bundle/Contents/Info.plist")"; \
			echo "Bundle version: $$version (expected $(VERSION))"; \
			test "$$version" = "$(VERSION)" || { \
				echo "error: the bundle reports $$version, but $(VERSION) was expected."; \
				exit 1; \
			}; \
		else \
			echo "Bundle version: $$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' "$$bundle/Contents/Info.plist") (no VERSION given)"; \
		fi; \
		codesign --verify --deep --strict "$$bundle"; \
		echo "Verified $$bundle."; \
	done

## install — copy the bundle of this machine into /Applications

install: $(HOST_APP_TARGET)
	@if [ -z "$(strip $(HOST_BUNDLE))" ]; then \
		echo "error: no bundle for the host architecture $(HOST_ARCH)."; \
		exit 1; \
	fi
	@mkdir -p "$(INSTALL_DIR)"
	@rm -rf "$(INSTALL_APP)"
	ditto "$(HOST_BUNDLE)" "$(INSTALL_APP)"
	@echo "Installed $(INSTALL_APP)"

## run — install the bundle and launch it

run: install
	open "$(INSTALL_APP)"

## dmg — both disk images

dmg: dmg-arm dmg-intel

## dmg-arm — the Apple silicon disk image

dmg-arm:
	MARKETING_VERSION="$(VERSION)" CURRENT_PROJECT_VERSION="$(BUILD_NUMBER)" \
		./build-dmg.sh dmg $(ARCH_ARM) "$(CONFIGURATION)"

## dmg-intel — the Intel disk image

dmg-intel:
	MARKETING_VERSION="$(VERSION)" CURRENT_PROJECT_VERSION="$(BUILD_NUMBER)" \
		./build-dmg.sh dmg $(ARCH_INTEL) "$(CONFIGURATION)"

## release-artifacts — the versioned disk images and their checksums

release-artifacts: _require_version dmg
	@mkdir -p "$(RELEASE_DIR)"
	cp "$(DMG_ARM)" "$(RELEASE_DIR)/$(APP_NAME)-$(VERSION)-$(ARCH_ARM).dmg"
	cp "$(DMG_INTEL)" "$(RELEASE_DIR)/$(APP_NAME)-$(VERSION)-$(ARCH_INTEL).dmg"
	@cd "$(RELEASE_DIR)" && shasum -a 256 "$(APP_NAME)-$(VERSION)-$(ARCH_ARM).dmg" "$(APP_NAME)-$(VERSION)-$(ARCH_INTEL).dmg" > checksums.txt
	@cd "$(RELEASE_DIR)" && shasum -a 256 -c checksums.txt
	@echo "$(RELEASE_DIR)/checksums.txt:"
	@cat "$(RELEASE_DIR)/checksums.txt"

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
