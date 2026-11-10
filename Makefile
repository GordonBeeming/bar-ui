.PHONY: build test bundle install run clean

# Prefer a real Apple Development identity over ad-hoc signing. Ad-hoc signing
# (`-`) mints a new identity every build, so any macOS permission grant tied to
# the code signature is lost on rebuild; a stable dev identity keeps it.
CODESIGN_IDENTITY ?= $(shell security find-identity -v -p codesigning 2>/dev/null | awk -F '"' '/Apple Development/{print $$2; exit}')

BUILD ?= 1
CODESIGN_OPTS ?=

# CI passes VERSION (the release tag without its "v") and BUILD. Without a
# VERSION this is a local build: it takes the last tag so the app doesn't claim
# a number nobody released, and says it is a dev build and from which commit.
ifeq ($(origin VERSION),undefined)
VERSION := $(or $(shell git describe --tags --abbrev=0 2>/dev/null | sed 's/^v//'),0.0)
DISPLAY_VERSION := $(VERSION)-dev ($(or $(shell git rev-parse --short HEAD 2>/dev/null),unknown))
else
DISPLAY_VERSION := $(VERSION) ($(BUILD))
endif

# What the app shows people. CFBundleShortVersionString has to stay numeric, so
# the dev suffix and commit live in their own key. Set-then-Add keeps a rerun
# against an existing plist working.
define stamp_display_version
/usr/libexec/PlistBuddy -c "Set :GBDisplayVersion $(DISPLAY_VERSION)" $(1) 2>/dev/null || \
	/usr/libexec/PlistBuddy -c "Add :GBDisplayVersion string $(DISPLAY_VERSION)" $(1)
endef

INSTALL_DIR ?= /Applications

APP_BUNDLE := dist/BarUI.app
# SMAppService.loginItem(identifier:) only finds helpers at this path.
HELPER_BUNDLE := $(APP_BUNDLE)/Contents/Library/LoginItems/BarUIHelper.app

build:
	swift build -c release

test:
	swift test

bundle: build
	rm -rf $(APP_BUNDLE)
	mkdir -p $(APP_BUNDLE)/Contents/MacOS $(APP_BUNDLE)/Contents/Resources
	cp .build/release/BarUI $(APP_BUNDLE)/Contents/MacOS/
	cp Packaging/AppIcon.icns $(APP_BUNDLE)/Contents/Resources/
	cp Packaging/Info.plist $(APP_BUNDLE)/Contents/Info.plist
	/usr/libexec/PlistBuddy \
		-c "Set :CFBundleShortVersionString $(VERSION)" \
		-c "Set :CFBundleVersion $(VERSION).$(BUILD)" \
		$(APP_BUNDLE)/Contents/Info.plist
	$(call stamp_display_version,$(APP_BUNDLE)/Contents/Info.plist)
	mkdir -p $(HELPER_BUNDLE)/Contents/MacOS
	cp .build/release/BarUIHelper $(HELPER_BUNDLE)/Contents/MacOS/
	cp Packaging/Helper-Info.plist $(HELPER_BUNDLE)/Contents/Info.plist
	/usr/libexec/PlistBuddy \
		-c "Set :CFBundleShortVersionString $(VERSION)" \
		-c "Set :CFBundleVersion $(VERSION).$(BUILD)" \
		$(HELPER_BUNDLE)/Contents/Info.plist
	$(call stamp_display_version,$(HELPER_BUNDLE)/Contents/Info.plist)
	# The helper is signed first: signing the app seals what is inside it.
	IDENT="$(CODESIGN_IDENTITY)"; [ -n "$$IDENT" ] || IDENT="-"; \
	codesign --force --sign "$$IDENT" --identifier com.gordonbeeming.BarUI.Helper $(CODESIGN_OPTS) $(HELPER_BUNDLE) && \
	codesign --force --sign "$$IDENT" --identifier com.gordonbeeming.BarUI $(CODESIGN_OPTS) $(APP_BUNDLE)

# The helper keeps its Archive connection open for as long as it runs, and a
# new build may upgrade the Archive's schema on first open. A helper left over
# from the old build would then fail against the upgraded file, so it is
# stopped with the app and started again afterwards if it was running. It is
# started again even when the copy fails, from where it ran before, so a
# failed install never leaves importing stopped.
install: bundle
	pkill -x BarUI || true
	@helper_pid=$$(pgrep -x BarUIHelper | head -n 1); \
	previous_helper=""; \
	if [ -n "$$helper_pid" ]; then \
		previous_helper=$$(ps -o comm= -p "$$helper_pid" | sed 's|/Contents/MacOS/BarUIHelper$$||'); \
	fi; \
	pkill -x BarUIHelper || true; \
	status=0; \
	ditto $(APP_BUNDLE) $(INSTALL_DIR)/BarUI.app || status=$$?; \
	if [ "$$status" -eq 0 ]; then \
		rm -rf dist; \
		[ -z "$$previous_helper" ] || previous_helper="$(INSTALL_DIR)/BarUI.app/Contents/Library/LoginItems/BarUIHelper.app"; \
	fi; \
	if [ -n "$$previous_helper" ]; then \
		open -g "$$previous_helper"; restart=$$?; \
		[ "$$status" -ne 0 ] || status=$$restart; \
	fi; \
	if [ "$$status" -eq 0 ]; then echo "Launch with: open $(INSTALL_DIR)/BarUI.app"; fi; \
	exit "$$status"

run:
	swift run

clean:
	rm -rf .build dist
