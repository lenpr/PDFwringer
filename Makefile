SDK := $(shell xcrun --sdk macosx --show-sdk-path)
SDK_PLATFORM_PATH := $(shell xcrun --sdk macosx --show-sdk-platform-path)
TARGET := arm64-apple-macosx26.0
SWIFT_LANGUAGE_FLAGS := -swift-version 6 -strict-concurrency=complete
SWIFT_FLAGS := -target $(TARGET) -sdk $(SDK) $(SWIFT_LANGUAGE_FLAGS) -parse-as-library -framework SwiftUI -framework PDFKit -framework AppKit
RELEASE_FLAGS := -O -whole-module-optimization
SIGN_IDENTITY ?= Developer ID Application: Lukas N.P. Egger (7DGU3C2XRL)
ENTITLEMENTS := PDFwringer/PDFwringer.entitlements
INFO_PLIST := PDFwringer/Info.plist
BUNDLE_VERSION := $(shell /usr/libexec/PlistBuddy -c "Print :CFBundleShortVersionString" $(INFO_PLIST))
NOTARY_PROFILE ?= notarytool-profile
SOURCES := $(shell find PDFwringer -name '*.swift' | LC_ALL=C sort)
TEST_SOURCES := $(shell find PDFwringerTests -name '*.swift' | LC_ALL=C sort)
TESTABLE_SOURCES := $(shell find PDFwringer/Services PDFwringer/Models PDFwringer/Utilities PDFwringer/ViewModels -name '*.swift' | LC_ALL=C sort)
BUILD_DIR := .build
APP_NAME := PDFwringer
APP_BUNDLE := $(BUILD_DIR)/$(APP_NAME).app
DMG := $(BUILD_DIR)/$(APP_NAME).dmg
TEST_NAME := PDFwringerTests
APP_SOURCE_HASH := $(shell printf '%s\n' $(SOURCES) | shasum -a 256 | cut -d ' ' -f 1)
TEST_SOURCE_HASH := $(shell printf '%s\n' $(TESTABLE_SOURCES) $(TEST_SOURCES) | shasum -a 256 | cut -d ' ' -f 1)
APP_SOURCE_STAMP := $(BUILD_DIR)/app-sources-$(APP_SOURCE_HASH).stamp
TEST_SOURCE_STAMP := $(BUILD_DIR)/test-sources-$(TEST_SOURCE_HASH).stamp
FIXTURE_CHECKSUMS := PDFwringerTests/Fixtures/SHA256SUMS
CORPUS_TEST_FILTER := DifferentialEquivalenceTests|Fixture.*Tests|PageGeometryTests|PerformanceBoundsTests|TextPreservationTests|VisualRegressionTests

# Keep the compiler plugin, framework, and runtime on the active Xcode toolchain.
SWIFT_LIB_DIR := $(shell dirname $$(dirname $$(xcrun --find swift)))/lib
TESTING_PLUGIN := $(SWIFT_LIB_DIR)/swift/host/plugins/testing/libTestingMacros.dylib
TESTING_FW_DIR := $(SDK_PLATFORM_PATH)/Developer/Library/Frameworks
TESTING_RPATH_DIR := $(SDK_PLATFORM_PATH)/Developer/usr/lib

.DEFAULT_GOAL := build

.PHONY: build clean run test test-fast test-corpus verify-fixtures verify-release-inputs verify-release-tag app release dmg sign notarize

$(APP_SOURCE_STAMP):
	@mkdir -p $(BUILD_DIR)
	@find $(BUILD_DIR) -maxdepth 1 -type f -name 'app-sources-*.stamp' \
		! -name '$(notdir $@)' -delete
	@touch $@

$(TEST_SOURCE_STAMP):
	@mkdir -p $(BUILD_DIR)
	@find $(BUILD_DIR) -maxdepth 1 -type f -name 'test-sources-*.stamp' \
		! -name '$(notdir $@)' -delete
	@touch $@

build: $(BUILD_DIR)/$(APP_NAME)

$(BUILD_DIR)/$(APP_NAME): Makefile $(APP_SOURCE_STAMP) $(SOURCES)
	@mkdir -p $(BUILD_DIR)
	swiftc $(SWIFT_FLAGS) -o $@ $(SOURCES)

app: $(APP_BUNDLE)

$(APP_BUNDLE): Makefile $(BUILD_DIR)/$(APP_NAME) $(ENTITLEMENTS) $(INFO_PLIST) PDFwringer/Resources/AppIcon.icns
	@rm -rf $(APP_BUNDLE)
	@mkdir -p $(APP_BUNDLE)/Contents/MacOS
	@mkdir -p $(APP_BUNDLE)/Contents/Resources
	@cp $(BUILD_DIR)/$(APP_NAME) $(APP_BUNDLE)/Contents/MacOS/$(APP_NAME)
	@cp PDFwringer/Resources/AppIcon.icns $(APP_BUNDLE)/Contents/Resources/AppIcon.icns
	@cp $(INFO_PLIST) $(APP_BUNDLE)/Contents/Info.plist
	@xattr -cr $(APP_BUNDLE)
	@codesign --force --options runtime --sign - \
		--entitlements $(ENTITLEMENTS) $(APP_BUNDLE)
	@codesign --verify --deep --strict $(APP_BUNDLE)
	@echo "Built $(APP_BUNDLE) (sandboxed, hardened runtime, ad-hoc signed)"

release:
	@$(MAKE) -B SWIFT_FLAGS='$(SWIFT_FLAGS) $(RELEASE_FLAGS)' app
	@echo "Release build ready at $(APP_BUNDLE)"

verify-release-inputs:
	@dirty_inputs=$$(git status --porcelain --untracked-files=all -- Makefile PDFwringer); \
	if [ -n "$$dirty_inputs" ]; then \
		echo "Refusing signed release: artifact inputs contain uncommitted changes:" >&2; \
		echo "$$dirty_inputs" >&2; \
		exit 1; \
	fi

verify-release-tag: verify-release-inputs
	@expected_tag="v$(BUNDLE_VERSION)"; \
	actual_tag=$$(git describe --tags --exact-match 2>/dev/null || true); \
	if [ "$$actual_tag" != "$$expected_tag" ]; then \
		echo "Refusing signed release: HEAD must be tagged $$expected_tag (found $${actual_tag:-no exact tag})." >&2; \
		exit 1; \
	fi

sign: verify-release-tag
	@$(MAKE) release
	@xattr -cr $(APP_BUNDLE)
	@codesign --force --options runtime --timestamp --sign "$(SIGN_IDENTITY)" \
		--entitlements $(ENTITLEMENTS) $(APP_BUNDLE)
	@codesign --verify --deep --strict --verbose=2 $(APP_BUNDLE)
	@codesign -dvvv $(APP_BUNDLE) 2>&1 | grep -q '^Authority=Developer ID Application:' || { \
		echo "Refusing signed release: SIGN_IDENTITY did not produce a Developer ID Application signature." >&2; \
		exit 1; \
	}
	@echo "Signed $(APP_BUNDLE) with Developer ID"

notarize: sign
	@set -e; \
	notary_work=$$(mktemp -d -t PDFwringer-notary); \
	trap 'rm -rf "$$notary_work"' EXIT; \
	archive="$$notary_work/$(APP_NAME).zip"; \
	ditto -c -k --keepParent $(APP_BUNDLE) "$$archive"; \
	xcrun notarytool submit "$$archive" --keychain-profile "$(NOTARY_PROFILE)" --wait; \
	xcrun stapler staple $(APP_BUNDLE); \
	xcrun stapler validate $(APP_BUNDLE)
	@echo "Notarized and stapled $(APP_BUNDLE)"

test: verify-fixtures $(BUILD_DIR)/$(TEST_NAME)
	$(BUILD_DIR)/$(TEST_NAME)

# Fast lane: unit + viewmodel + safety tests only (no fixtures, <5s)
test-fast: $(BUILD_DIR)/$(TEST_NAME)
	$(BUILD_DIR)/$(TEST_NAME) --skip "$(CORPUS_TEST_FILTER)"

# Slow/corpus lane: fixture, invariant, visual, differential, and performance tests
test-corpus: verify-fixtures $(BUILD_DIR)/$(TEST_NAME)
	$(BUILD_DIR)/$(TEST_NAME) --filter "$(CORPUS_TEST_FILTER)"

verify-fixtures: $(FIXTURE_CHECKSUMS)
	@expected_count=$$(wc -l < $(FIXTURE_CHECKSUMS) | tr -d ' '); \
	actual_count=$$(find PDFwringerTests/Fixtures -type f -name '*.pdf' | wc -l | tr -d ' '); \
	if [ "$$actual_count" -ne "$$expected_count" ]; then \
		echo "Fixture corpus is incomplete: expected $$expected_count PDFs, found $$actual_count." >&2; \
		echo "See PDFwringerTests/Fixtures/README.md for setup details." >&2; \
		exit 1; \
	fi
	@shasum -a 256 --quiet --strict --check $(FIXTURE_CHECKSUMS) || { \
		echo "Fixture corpus checksum validation failed." >&2; \
		exit 1; \
	}
	@echo "Verified external fixture corpus."

$(BUILD_DIR)/$(TEST_NAME): Makefile $(TEST_SOURCE_STAMP) $(TESTABLE_SOURCES) $(TEST_SOURCES)
	@mkdir -p $(BUILD_DIR)
	swiftc -target $(TARGET) -sdk $(SDK) $(SWIFT_LANGUAGE_FLAGS) -parse-as-library \
		-framework PDFKit -framework AppKit -framework Foundation \
		-F $(TESTING_FW_DIR) \
		-framework Testing \
		-Xlinker -rpath -Xlinker $(TESTING_FW_DIR) \
		-Xlinker -rpath -Xlinker $(TESTING_RPATH_DIR) \
		-load-plugin-library $(TESTING_PLUGIN) \
		-module-name PDFwringer \
		-o $@ \
		$(TESTABLE_SOURCES) $(TEST_SOURCES)

dmg: sign
	@set -e; \
	dmg_work=$$(mktemp -d -t PDFwringer-dmg); \
	trap 'rm -rf "$$dmg_work"' EXIT; \
	payload="$$dmg_work/payload"; \
	temporary_dmg="$$dmg_work/$(APP_NAME).dmg"; \
	mkdir "$$payload"; \
	cp -R $(APP_BUNDLE) "$$payload/"; \
	ln -s /Applications "$$payload/Applications"; \
	hdiutil create -volname "$(APP_NAME)" -srcfolder "$$payload" \
		-format UDZO "$$temporary_dmg" >/dev/null; \
	codesign --force --timestamp --sign "$(SIGN_IDENTITY)" "$$temporary_dmg"; \
	codesign --verify --strict --verbose=2 "$$temporary_dmg"; \
	xcrun notarytool submit "$$temporary_dmg" --keychain-profile "$(NOTARY_PROFILE)" --wait; \
	xcrun stapler staple "$$temporary_dmg"; \
	xcrun stapler validate "$$temporary_dmg"; \
	hdiutil verify "$$temporary_dmg"; \
	mv "$$temporary_dmg" $(DMG)
	@echo "Built signed and notarized $(DMG)"

clean:
	rm -rf $(BUILD_DIR)

run: app
	open -n "$(APP_BUNDLE)"
