.PHONY: build test bundle install run clean

# Prefer a real Apple Development identity over ad-hoc signing. Ad-hoc signing
# (`-`) mints a new identity every build, so any macOS permission grant tied to
# the code signature is lost on rebuild; a stable dev identity keeps it.
CODESIGN_IDENTITY ?= $(shell security find-identity -v -p codesigning 2>/dev/null | awk -F '"' '/Apple Development/{print $$2; exit}')

VERSION ?= 1.0.0
BUILD ?= 1
CODESIGN_OPTS ?=

INSTALL_DIR ?= /Applications

APP_BUNDLE := dist/BarUI.app

build:
	swift build -c release

test:
	swift test

bundle: build
	rm -rf $(APP_BUNDLE)
	mkdir -p $(APP_BUNDLE)/Contents/MacOS $(APP_BUNDLE)/Contents/Resources
	cp .build/release/BarUI $(APP_BUNDLE)/Contents/MacOS/
	cp Packaging/Info.plist $(APP_BUNDLE)/Contents/Info.plist
	/usr/libexec/PlistBuddy \
		-c "Set :CFBundleShortVersionString $(VERSION)" \
		-c "Set :CFBundleVersion $(VERSION).$(BUILD)" \
		$(APP_BUNDLE)/Contents/Info.plist
	IDENT="$(CODESIGN_IDENTITY)"; [ -n "$$IDENT" ] || IDENT="-"; \
	codesign --force --sign "$$IDENT" --identifier com.gordonbeeming.BarUI $(CODESIGN_OPTS) $(APP_BUNDLE)

install: bundle
	pkill -x BarUI || true
	ditto $(APP_BUNDLE) $(INSTALL_DIR)/BarUI.app
	rm -rf dist
	@echo "Launch with: open $(INSTALL_DIR)/BarUI.app"

run:
	swift run

clean:
	rm -rf .build dist
