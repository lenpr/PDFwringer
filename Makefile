SDK := $(shell xcrun --sdk macosx --show-sdk-path)
SDK_PLATFORM_PATH := $(shell xcrun --sdk macosx --show-sdk-platform-path)
SDK_VERSION := $(shell xcrun --sdk macosx --show-sdk-version)
SWIFTC := $(shell xcrun --find swiftc)
SWIFTC_VERSION := $(shell "$(SWIFTC)" --version 2>&1 | tr '\n' ' ')
TARGET := arm64-apple-macosx26.0
SWIFT_LANGUAGE_FLAGS := -swift-version 6 -strict-concurrency=complete
SWIFT_FLAGS := -target $(TARGET) -sdk $(SDK) $(SWIFT_LANGUAGE_FLAGS) -parse-as-library -framework SwiftUI -framework PDFKit -framework AppKit
RELEASE_FLAGS := -O -whole-module-optimization
SIGN_IDENTITY ?= Developer ID Application: Lukas N.P. Egger (7DGU3C2XRL)
ENTITLEMENTS := PDFwringer/PDFwringer.entitlements
INFO_PLIST := PDFwringer/Info.plist
PRIVACY_MANIFEST := PDFwringer/PrivacyInfo.xcprivacy
BUNDLE_VERSION := $(shell /usr/libexec/PlistBuddy -c "Print :CFBundleShortVersionString" $(INFO_PLIST))
BUNDLE_BUILD := $(shell /usr/libexec/PlistBuddy -c "Print :CFBundleVersion" $(INFO_PLIST))
NOTARY_PROFILE ?= notarytool-profile
SOURCES := $(shell find PDFwringer -name '*.swift' | LC_ALL=C sort)
TEST_SOURCES := $(shell find PDFwringerTests -name '*.swift' | LC_ALL=C sort)
# Include the native PDF bridge so queued navigation and teardown can be tested.
TESTABLE_SOURCES := $(shell find PDFwringer/Services PDFwringer/Models PDFwringer/Utilities PDFwringer/ViewModels -name '*.swift' | LC_ALL=C sort) PDFwringer/Views/PDFPreviewView.swift
BUILD_DIR := .build
APP_NAME := PDFwringer
APP_BUNDLE := $(BUILD_DIR)/$(APP_NAME).app
DMG := $(BUILD_DIR)/$(APP_NAME).dmg
XCODE_PROJECT := PDFwringer.xcodeproj
XCODE_SCHEME := PDFwringer
APP_STORE_TEAM_ID ?=
APP_STORE_EXPORT_OPTIONS := Distribution/AppStoreExportOptions.plist
APP_STORE_ARTIFACT_DIR := $(BUILD_DIR)/app-store/$(APP_NAME)-$(BUNDLE_VERSION)-build.$(BUNDLE_BUILD)
APP_STORE_ARCHIVE := $(APP_STORE_ARTIFACT_DIR)/$(APP_NAME).xcarchive
APP_STORE_EXPORT_DIR := $(APP_STORE_ARTIFACT_DIR)/export
TEST_NAME := PDFwringerTests
FIXTURE_CHECKSUMS := PDFwringerTests/Fixtures/SHA256SUMS
CORPUS_TEST_FILTER := DifferentialEquivalenceTests|Fixture.*Tests|PageGeometryTests|TextPreservationTests|VisualRegressionTests
PERFORMANCE_TEST_FILTER := PerformanceBoundsTests
SLOW_TEST_FILTER := $(CORPUS_TEST_FILTER)|$(PERFORMANCE_TEST_FILTER)

# Keep the compiler plugin, framework, and runtime on the active Xcode toolchain.
SWIFT_LIB_DIR := $(shell dirname $$(dirname $$(xcrun --find swift)))/lib
TESTING_PLUGIN := $(SWIFT_LIB_DIR)/swift/host/plugins/testing/libTestingMacros.dylib
TESTING_FW_DIR := $(SDK_PLATFORM_PATH)/Developer/Library/Frameworks
TESTING_RPATH_DIR := $(SDK_PLATFORM_PATH)/Developer/usr/lib
APP_BUILD_HASH := $(shell printf '%s\n' '$(SWIFTC)' '$(SWIFTC_VERSION)' '$(SDK)' '$(SDK_VERSION)' '$(TARGET)' '$(SWIFT_FLAGS)' $(SOURCES) | shasum -a 256 | cut -d ' ' -f 1)
TEST_BUILD_HASH := $(shell printf '%s\n' '$(SWIFTC)' '$(SWIFTC_VERSION)' '$(SDK)' '$(SDK_VERSION)' '$(TARGET)' '$(SWIFT_LANGUAGE_FLAGS)' '$(TESTING_PLUGIN)' '$(TESTING_FW_DIR)' '$(TESTING_RPATH_DIR)' $(TESTABLE_SOURCES) $(TEST_SOURCES) | shasum -a 256 | cut -d ' ' -f 1)
APP_BUILD_STAMP := $(BUILD_DIR)/app-build-$(APP_BUILD_HASH).stamp
TEST_BUILD_STAMP := $(BUILD_DIR)/test-build-$(TEST_BUILD_HASH).stamp

.DEFAULT_GOAL := build

.PHONY: build clean run test test-fast test-corpus verify-fixtures verify-release-inputs verify-release-tag verify-app-store-metadata verify-app-store-inputs verify-app-store-tag verify-app-store-team app release dmg sign notarize app-store-check app-store-archive app-store-export

$(APP_BUILD_STAMP):
	@mkdir -p $(BUILD_DIR)
	@find $(BUILD_DIR) -maxdepth 1 -type f -name 'app-build-*.stamp' \
		! -name '$(notdir $@)' -delete
	@touch $@

$(TEST_BUILD_STAMP):
	@mkdir -p $(BUILD_DIR)
	@find $(BUILD_DIR) -maxdepth 1 -type f -name 'test-build-*.stamp' \
		! -name '$(notdir $@)' -delete
	@touch $@

build: $(BUILD_DIR)/$(APP_NAME)

$(BUILD_DIR)/$(APP_NAME): Makefile $(APP_BUILD_STAMP) $(SOURCES)
	@mkdir -p $(BUILD_DIR)
	$(SWIFTC) $(SWIFT_FLAGS) -o $@ $(SOURCES)

app: $(APP_BUNDLE)

$(APP_BUNDLE): Makefile $(BUILD_DIR)/$(APP_NAME) $(ENTITLEMENTS) $(INFO_PLIST) $(PRIVACY_MANIFEST) PDFwringer/Resources/AppIcon.icns
	@rm -rf $(APP_BUNDLE)
	@mkdir -p $(APP_BUNDLE)/Contents/MacOS
	@mkdir -p $(APP_BUNDLE)/Contents/Resources
	@cp $(BUILD_DIR)/$(APP_NAME) $(APP_BUNDLE)/Contents/MacOS/$(APP_NAME)
	@cp PDFwringer/Resources/AppIcon.icns $(APP_BUNDLE)/Contents/Resources/AppIcon.icns
	@cp $(PRIVACY_MANIFEST) $(APP_BUNDLE)/Contents/Resources/PrivacyInfo.xcprivacy
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
	@set -e; \
	dirty_inputs=$$(git status --porcelain --untracked-files=all -- Makefile PDFwringer); \
	if [ -n "$$dirty_inputs" ]; then \
		echo "Refusing signed release: artifact inputs contain uncommitted changes:" >&2; \
		echo "$$dirty_inputs" >&2; \
		exit 1; \
	fi

verify-release-tag: verify-release-inputs
	@expected_tag="v$(BUNDLE_VERSION)"; \
	actual_tags=$$(git tag --points-at HEAD); \
	if ! printf '%s\n' "$$actual_tags" | grep -Fqx "$$expected_tag"; then \
		echo "Refusing signed release: HEAD must include tag $$expected_tag (found $${actual_tags:-no exact tag})." >&2; \
		exit 1; \
	fi

verify-app-store-metadata: $(INFO_PLIST) $(ENTITLEMENTS) $(PRIVACY_MANIFEST) $(APP_STORE_EXPORT_OPTIONS)
	@plutil -lint $(INFO_PLIST) $(ENTITLEMENTS) $(PRIVACY_MANIFEST) $(APP_STORE_EXPORT_OPTIONS) >/dev/null
	@version='$(BUNDLE_VERSION)'; build='$(BUNDLE_BUILD)'; \
	if ! printf '%s\n' "$$version" | grep -Eq '^[0-9]+(\.[0-9]+){2}$$'; then \
		echo "Invalid CFBundleShortVersionString '$$version': expected three numeric components." >&2; \
		exit 1; \
	fi; \
	if ! printf '%s\n' "$$build" | grep -Eq '^[0-9]+(\.[0-9]+){0,2}$$'; then \
		echo "Invalid CFBundleVersion '$$build': expected one to three numeric components." >&2; \
		exit 1; \
	fi
	@test "$$(/usr/libexec/PlistBuddy -c 'Print :com.apple.security.app-sandbox' $(ENTITLEMENTS))" = true || { \
		echo "Mac App Store builds require the App Sandbox entitlement." >&2; \
		exit 1; \
	}
	@test "$$(/usr/libexec/PlistBuddy -c 'Print :com.apple.security.files.user-selected.read-write' $(ENTITLEMENTS))" = true || { \
		echo "The app requires user-selected read/write access for PDF workflows." >&2; \
		exit 1; \
	}
	@test "$$(/usr/libexec/PlistBuddy -c 'Print :NSPrivacyTracking' $(PRIVACY_MANIFEST))" = false || { \
		echo "Privacy manifest must match the app's no-tracking behavior." >&2; \
		exit 1; \
	}
	@test "$$(plutil -extract NSPrivacyTrackingDomains json -o - $(PRIVACY_MANIFEST))" = '[]' || { \
		echo "Privacy manifest must not declare tracking domains." >&2; \
		exit 1; \
	}
	@test "$$(plutil -extract NSPrivacyCollectedDataTypes json -o - $(PRIVACY_MANIFEST))" = '[]' || { \
		echo "Privacy manifest must match the app's no-collection behavior." >&2; \
		exit 1; \
	}
	@test "$$(/usr/libexec/PlistBuddy -c 'Print :LSApplicationCategoryType' $(INFO_PLIST))" = public.app-category.productivity || { \
		echo "Mac App Store category must remain configured in Info.plist." >&2; \
		exit 1; \
	}
	@bundle_id=$$(/usr/libexec/PlistBuddy -c 'Print :CFBundleIdentifier' $(INFO_PLIST)); \
	if ! printf '%s\n' "$$bundle_id" | grep -Eq '^[A-Za-z0-9-]+(\.[A-Za-z0-9-]+)+$$'; then \
		echo "Invalid CFBundleIdentifier '$$bundle_id'." >&2; \
		exit 1; \
	fi
	@test "$$(/usr/libexec/PlistBuddy -c 'Print :method' $(APP_STORE_EXPORT_OPTIONS))" = app-store-connect || { \
		echo "Export method must be app-store-connect." >&2; \
		exit 1; \
	}
	@test "$$(/usr/libexec/PlistBuddy -c 'Print :destination' $(APP_STORE_EXPORT_OPTIONS))" = export || { \
		echo "Export destination must remain local; repository targets do not upload." >&2; \
		exit 1; \
	}
	@test "$$(/usr/libexec/PlistBuddy -c 'Print :signingStyle' $(APP_STORE_EXPORT_OPTIONS))" = automatic || { \
		echo "App Store export must use Xcode automatic signing." >&2; \
		exit 1; \
	}
	@test "$$(/usr/libexec/PlistBuddy -c 'Print :manageAppVersionAndBuildNumber' $(APP_STORE_EXPORT_OPTIONS))" = false || { \
		echo "Xcode must preserve the reviewed Info.plist version and build number." >&2; \
		exit 1; \
	}
	@test "$$(/usr/libexec/PlistBuddy -c 'Print :uploadSymbols' $(APP_STORE_EXPORT_OPTIONS))" = true || { \
		echo "App Store exports must include symbols." >&2; \
		exit 1; \
	}
	@if /usr/libexec/PlistBuddy -c 'Print :teamID' $(APP_STORE_EXPORT_OPTIONS) >/dev/null 2>&1; then \
		echo "Do not commit a team ID; pass APP_STORE_TEAM_ID at invocation." >&2; \
		exit 1; \
	fi
	@icon=PDFwringer/Resources/Assets.xcassets/AppIcon.appiconset/icon_512x512@2x.png; \
	width=$$(sips -g pixelWidth "$$icon" 2>/dev/null | awk '/pixelWidth/ { print $$2 }'); \
	height=$$(sips -g pixelHeight "$$icon" 2>/dev/null | awk '/pixelHeight/ { print $$2 }'); \
	if [ "$$width" != 1024 ] || [ "$$height" != 1024 ]; then \
		echo "Mac App Store icon must include a 1024×1024 image." >&2; \
		exit 1; \
	fi
	@echo "Verified Mac App Store metadata for $(APP_NAME) $(BUNDLE_VERSION) ($(BUNDLE_BUILD))."

verify-app-store-inputs:
	@set -e; \
	dirty_inputs=$$(git status --porcelain --untracked-files=all -- Makefile PDFwringer PDFwringer.xcodeproj Distribution); \
	if [ -n "$$dirty_inputs" ]; then \
		echo "Refusing App Store release: archive inputs contain uncommitted changes:" >&2; \
		echo "$$dirty_inputs" >&2; \
		exit 1; \
	fi

verify-app-store-tag: verify-app-store-inputs verify-app-store-metadata
	@expected_tag="appstore-v$(BUNDLE_VERSION)-build.$(BUNDLE_BUILD)"; \
	actual_tags=$$(git tag --points-at HEAD); \
	if ! printf '%s\n' "$$actual_tags" | grep -Fqx "$$expected_tag"; then \
		echo "Refusing App Store release: HEAD must include tag $$expected_tag (found $${actual_tags:-no exact tag})." >&2; \
		exit 1; \
	fi

verify-app-store-team:
	@if ! printf '%s\n' '$(APP_STORE_TEAM_ID)' | grep -Eq '^[A-Z0-9]{10}$$'; then \
		echo "Set APP_STORE_TEAM_ID to the 10-character Apple Developer Team ID." >&2; \
		exit 1; \
	fi

# Credential-free structural check. The resulting temporary archive is unsigned,
# never uploaded, and removed when validation finishes.
app-store-check: verify-app-store-metadata
	@set -e; \
	check_work=$$(mktemp -d -t PDFwringer-app-store-check); \
	trap 'rm -rf "$$check_work"' EXIT; \
	archive="$$check_work/$(APP_NAME).xcarchive"; \
	xcodebuild -quiet -project $(XCODE_PROJECT) -scheme $(XCODE_SCHEME) \
		-configuration Release -destination 'generic/platform=macOS' \
		-archivePath "$$archive" CODE_SIGNING_ALLOWED=NO archive; \
	app="$$archive/Products/Applications/$(APP_NAME).app"; \
	test -f "$$app/Contents/Resources/PrivacyInfo.xcprivacy" || { \
		echo "PrivacyInfo.xcprivacy is missing from the archive." >&2; exit 1; \
	}; \
	test -f "$$app/Contents/Resources/AppIcon.icns" || { \
		echo "Compiled App Store icon is missing from the archive." >&2; exit 1; \
	}; \
	test -d "$$archive/dSYMs/$(APP_NAME).app.dSYM" || { \
		echo "Release dSYM is missing from the archive." >&2; exit 1; \
	}; \
	plutil -lint "$$app/Contents/Info.plist" "$$app/Contents/Resources/PrivacyInfo.xcprivacy" >/dev/null; \
	test "$$(/usr/libexec/PlistBuddy -c 'Print :CFBundleIdentifier' "$$app/Contents/Info.plist")" = "$$(/usr/libexec/PlistBuddy -c 'Print :CFBundleIdentifier' $(INFO_PLIST))"; \
	test "$$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' "$$app/Contents/Info.plist")" = '$(BUNDLE_VERSION)'; \
	test "$$(/usr/libexec/PlistBuddy -c 'Print :CFBundleVersion' "$$app/Contents/Info.plist")" = '$(BUNDLE_BUILD)'; \
	test "$$(lipo -archs "$$app/Contents/MacOS/$(APP_NAME)")" = arm64 || { \
		echo "Release archive must contain only Apple silicon (arm64) code." >&2; exit 1; \
	}; \
	if find "$$app" -xattrname com.apple.quarantine -print | grep -q .; then \
		echo "Archive contains a forbidden com.apple.quarantine attribute." >&2; exit 1; \
	fi; \
	echo "Verified unsigned Mac App Store archive structure."

# Creates a signed archive only. This target never uploads or notarizes anything.
app-store-archive: verify-app-store-tag verify-app-store-team
	@set -e; \
	mkdir -p "$(BUILD_DIR)/app-store"; \
	if ! mkdir "$(APP_STORE_ARTIFACT_DIR)"; then \
		echo "Refusing to overwrite or race an existing artifact directory: $(APP_STORE_ARTIFACT_DIR)" >&2; exit 1; \
	fi; \
	archive_work=; \
	published=false; \
	trap 'if [ -n "$$archive_work" ]; then rm -rf "$$archive_work"; fi; if [ "$$published" != true ]; then rmdir "$(APP_STORE_ARTIFACT_DIR)" 2>/dev/null || true; fi' EXIT; \
	archive_work=$$(mktemp -d -t PDFwringer-app-store-archive); \
	xcodebuild -quiet -project $(XCODE_PROJECT) -scheme $(XCODE_SCHEME) \
		-configuration Release -destination 'generic/platform=macOS' \
		-archivePath "$$archive_work/$(APP_NAME).xcarchive" \
		DEVELOPMENT_TEAM='$(APP_STORE_TEAM_ID)' \
		-allowProvisioningUpdates archive; \
	app="$$archive_work/$(APP_NAME).xcarchive/Products/Applications/$(APP_NAME).app"; \
	test "$$(lipo -archs "$$app/Contents/MacOS/$(APP_NAME)")" = arm64 || { \
		echo "Release archive must contain only Apple silicon (arm64) code." >&2; exit 1; \
	}; \
	codesign --verify --deep --strict "$$app"; \
	actual_team=$$(codesign -dvv "$$app" 2>&1 | awk -F= '/^TeamIdentifier=/ { print $$2 }'); \
	if [ "$$actual_team" != '$(APP_STORE_TEAM_ID)' ]; then \
		echo "Archive team '$$actual_team' does not match APP_STORE_TEAM_ID." >&2; exit 1; \
	fi; \
	codesign -d --entitlements :- "$$app" > "$$archive_work/EffectiveEntitlements.plist" 2>/dev/null; \
	for entitlement in com.apple.security.app-sandbox com.apple.security.files.user-selected.read-write com.apple.security.files.bookmarks.app-scope; do \
		if [ "$$(/usr/libexec/PlistBuddy -c "Print :$$entitlement" "$$archive_work/EffectiveEntitlements.plist")" != true ]; then \
			echo "Signed archive is missing required entitlement $$entitlement." >&2; exit 1; \
		fi; \
	done; \
	if [ -e "$(APP_STORE_ARCHIVE)" ]; then \
		echo "Archive destination appeared while building; refusing to merge it." >&2; exit 1; \
	fi; \
	mv "$$archive_work/$(APP_NAME).xcarchive" "$(APP_STORE_ARCHIVE)"; \
	published=true; \
	echo "Created App Store archive at $(APP_STORE_ARCHIVE)"

# Exports a locally uploadable package. Upload remains an explicit Organizer or
# Transporter action so this command cannot publish accidentally.
app-store-export: verify-app-store-tag verify-app-store-team
	@set -e; \
	if [ ! -d "$(APP_STORE_ARCHIVE)" ]; then \
		echo "Archive not found; run 'make app-store-archive APP_STORE_TEAM_ID=$(APP_STORE_TEAM_ID)' first." >&2; exit 1; \
	fi; \
	if [ -e "$(APP_STORE_EXPORT_DIR)" ]; then \
		echo "Refusing to overwrite existing export: $(APP_STORE_EXPORT_DIR)" >&2; exit 1; \
	fi; \
	export_lock="$(APP_STORE_ARTIFACT_DIR)/.export-lock"; \
	if ! mkdir "$$export_lock"; then \
		echo "Another export is already using this archive." >&2; exit 1; \
	fi; \
	export_work=; \
	trap 'if [ -n "$$export_work" ]; then rm -rf "$$export_work"; fi; rmdir "$$export_lock" 2>/dev/null || true' EXIT; \
	export_work=$$(mktemp -d -t PDFwringer-app-store-export); \
	cp $(APP_STORE_EXPORT_OPTIONS) "$$export_work/ExportOptions.plist"; \
	plutil -insert teamID -string '$(APP_STORE_TEAM_ID)' "$$export_work/ExportOptions.plist"; \
	xcodebuild -quiet -exportArchive -archivePath "$(APP_STORE_ARCHIVE)" \
		-exportPath "$$export_work/export" \
		-exportOptionsPlist "$$export_work/ExportOptions.plist" \
		-allowProvisioningUpdates; \
	package_count=$$(find "$$export_work/export" -maxdepth 1 -type f -name '*.pkg' | wc -l | tr -d ' '); \
	if [ "$$package_count" -ne 1 ]; then \
		echo "Expected exactly one Mac App Store package; found $$package_count." >&2; exit 1; \
	fi; \
	package=$$(find "$$export_work/export" -maxdepth 1 -type f -name '*.pkg' -print -quit); \
	pkgutil --check-signature "$$package" >/dev/null; \
	if [ -e "$(APP_STORE_EXPORT_DIR)" ]; then \
		echo "Export destination appeared while building; refusing to merge it." >&2; exit 1; \
	fi; \
	mv "$$export_work/export" "$(APP_STORE_EXPORT_DIR)"; \
	echo "Exported App Store package to $(APP_STORE_EXPORT_DIR)"

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
	$(BUILD_DIR)/$(TEST_NAME) --skip "$(SLOW_TEST_FILTER)"
	$(BUILD_DIR)/$(TEST_NAME) --filter "$(CORPUS_TEST_FILTER)"
	$(BUILD_DIR)/$(TEST_NAME) --filter "$(PERFORMANCE_TEST_FILTER)"

# Fast lane: unit + viewmodel + safety tests only (no fixtures, <5s)
test-fast: $(BUILD_DIR)/$(TEST_NAME)
	$(BUILD_DIR)/$(TEST_NAME) --skip "$(SLOW_TEST_FILTER)"

# Slow lane: corpus tests first, then performance bounds without corpus contention.
test-corpus: verify-fixtures $(BUILD_DIR)/$(TEST_NAME)
	$(BUILD_DIR)/$(TEST_NAME) --filter "$(CORPUS_TEST_FILTER)"
	$(BUILD_DIR)/$(TEST_NAME) --filter "$(PERFORMANCE_TEST_FILTER)"

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

$(BUILD_DIR)/$(TEST_NAME): Makefile $(TEST_BUILD_STAMP) $(TESTABLE_SOURCES) $(TEST_SOURCES)
	@mkdir -p $(BUILD_DIR)
	$(SWIFTC) -target $(TARGET) -sdk $(SDK) $(SWIFT_LANGUAGE_FLAGS) -parse-as-library \
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
