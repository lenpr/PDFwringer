SDK := $(shell xcrun --show-sdk-path)
TARGET := arm64-apple-macosx26.0
SWIFT_FLAGS := -target $(TARGET) -sdk $(SDK) -parse-as-library -framework SwiftUI -framework PDFKit -framework AppKit
RELEASE_FLAGS := -O -whole-module-optimization
VERSION := $(shell git describe --tags --abbrev=0 2>/dev/null || echo "dev")
SIGN_IDENTITY := Developer ID Application: Lukas N.P. Egger (7DGU3C2XRL)
ENTITLEMENTS := PDFwringer/PDFwringer.entitlements
NOTARY_PROFILE := notarytool-profile
# Generate version file only when content changes
$(shell NEW_VER='let appVersion = "$(VERSION)"'; \
    if [ ! -f PDFwringer/GeneratedVersion.swift ] || [ "$$(cat PDFwringer/GeneratedVersion.swift)" != "$$NEW_VER" ]; then \
        printf '%s' "$$NEW_VER" > PDFwringer/GeneratedVersion.swift; \
    fi)
SOURCES := $(shell find PDFwringer -name '*.swift')
TEST_SOURCES := $(shell find PDFwringerTests -name '*.swift')
TESTABLE_SOURCES := $(shell find PDFwringer/Services PDFwringer/Models PDFwringer/Utilities PDFwringer/ViewModels -name '*.swift')
BUILD_DIR := .build
APP_NAME := PDFwringer
APP_BUNDLE := $(BUILD_DIR)/$(APP_NAME).app
TEST_NAME := PDFwringerTests

# Derive Testing framework paths from active toolchain
SWIFT_LIB_DIR := $(shell dirname $$(dirname $$(xcrun --find swift)))/lib
TESTING_PLUGIN := $(SWIFT_LIB_DIR)/swift/host/plugins/testing/libTestingMacros.dylib
DEVELOPER_DIR := $(shell xcode-select -p)
TESTING_FW_DIR := $(DEVELOPER_DIR)/Library/Developer/Frameworks
TESTING_RPATH_DIR := $(DEVELOPER_DIR)/Library/Developer/usr/lib
# Fallback for CommandLineTools layout
ifeq ($(wildcard $(TESTING_FW_DIR)/Testing.framework),)
    TESTING_FW_DIR := /Library/Developer/CommandLineTools/Library/Developer/Frameworks
    TESTING_RPATH_DIR := /Library/Developer/CommandLineTools/Library/Developer/usr/lib
endif

.PHONY: build clean run test test-fast test-corpus app release dmg sign notarize

build: $(BUILD_DIR)/$(APP_NAME)

$(BUILD_DIR)/$(APP_NAME): $(SOURCES)
	@mkdir -p $(BUILD_DIR)
	swiftc $(SWIFT_FLAGS) -o $@ $(SOURCES)

app: $(APP_BUNDLE)

$(APP_BUNDLE): $(BUILD_DIR)/$(APP_NAME)
	@rm -rf $(APP_BUNDLE)
	@mkdir -p $(APP_BUNDLE)/Contents/MacOS
	@mkdir -p $(APP_BUNDLE)/Contents/Resources
	@cp $(BUILD_DIR)/$(APP_NAME) $(APP_BUNDLE)/Contents/MacOS/$(APP_NAME)
	@cp PDFwringer/Resources/AppIcon.icns $(APP_BUNDLE)/Contents/Resources/AppIcon.icns
	@/usr/libexec/PlistBuddy -c "Add :CFBundleExecutable string $(APP_NAME)" $(APP_BUNDLE)/Contents/Info.plist
	@/usr/libexec/PlistBuddy -c "Add :CFBundleIdentifier string com.pdfwringer.app" $(APP_BUNDLE)/Contents/Info.plist
	@/usr/libexec/PlistBuddy -c "Add :CFBundleName string $(APP_NAME)" $(APP_BUNDLE)/Contents/Info.plist
	@/usr/libexec/PlistBuddy -c "Add :CFBundlePackageType string APPL" $(APP_BUNDLE)/Contents/Info.plist
	@/usr/libexec/PlistBuddy -c "Add :CFBundleShortVersionString string $(VERSION)" $(APP_BUNDLE)/Contents/Info.plist
	@/usr/libexec/PlistBuddy -c "Add :CFBundleVersion string 1" $(APP_BUNDLE)/Contents/Info.plist
	@/usr/libexec/PlistBuddy -c "Add :CFBundleIconFile string AppIcon" $(APP_BUNDLE)/Contents/Info.plist
	@/usr/libexec/PlistBuddy -c "Add :LSMinimumSystemVersion string 26.0" $(APP_BUNDLE)/Contents/Info.plist
	@/usr/libexec/PlistBuddy -c "Add :NSHighResolutionCapable bool true" $(APP_BUNDLE)/Contents/Info.plist
	@/usr/libexec/PlistBuddy -c "Add :CFBundleDocumentTypes array" $(APP_BUNDLE)/Contents/Info.plist
	@/usr/libexec/PlistBuddy -c "Add :CFBundleDocumentTypes:0 dict" $(APP_BUNDLE)/Contents/Info.plist
	@/usr/libexec/PlistBuddy -c "Add :CFBundleDocumentTypes:0:CFBundleTypeName string PDF Document" $(APP_BUNDLE)/Contents/Info.plist
	@/usr/libexec/PlistBuddy -c "Add :CFBundleDocumentTypes:0:CFBundleTypeRole string Viewer" $(APP_BUNDLE)/Contents/Info.plist
	@/usr/libexec/PlistBuddy -c "Add :CFBundleDocumentTypes:0:LSItemContentTypes array" $(APP_BUNDLE)/Contents/Info.plist
	@/usr/libexec/PlistBuddy -c "Add :CFBundleDocumentTypes:0:LSItemContentTypes:0 string com.adobe.pdf" $(APP_BUNDLE)/Contents/Info.plist
	@/usr/libexec/PlistBuddy -c "Add :CFBundleDocumentTypes:0:LSHandlerRank string Alternate" $(APP_BUNDLE)/Contents/Info.plist
	@xattr -cr $(APP_BUNDLE) 2>/dev/null || true
	@codesign --force --sign - --entitlements $(ENTITLEMENTS) $(APP_BUNDLE) 2>/dev/null \
		&& echo "Built $(APP_BUNDLE) (ad-hoc signed with sandbox entitlements)" \
		|| (codesign --force --sign - $(APP_BUNDLE) 2>/dev/null; echo "Built $(APP_BUNDLE) (WARNING: sandbox entitlements not applied — use 'make sign' for sandboxed builds)")

sign: app
	@rm -rf /tmp/PDFwringer_build
	@mkdir -p /tmp/PDFwringer_build
	@cp -R $(APP_BUNDLE) /tmp/PDFwringer_build/$(APP_NAME).app
	@xattr -cr /tmp/PDFwringer_build/$(APP_NAME).app
	@codesign --force --options runtime --sign "$(SIGN_IDENTITY)" \
		--entitlements $(ENTITLEMENTS) /tmp/PDFwringer_build/$(APP_NAME).app
	@rm -rf $(APP_BUNDLE)
	@cp -R /tmp/PDFwringer_build/$(APP_NAME).app $(APP_BUNDLE)
	@rm -rf /tmp/PDFwringer_build
	@echo "Signed $(APP_BUNDLE) with Developer ID"

notarize: sign
	@echo "Creating zip for notarization..."
	@ditto -c -k --keepParent $(APP_BUNDLE) $(BUILD_DIR)/$(APP_NAME).zip
	@echo "Submitting to Apple for notarization..."
	@xcrun notarytool submit $(BUILD_DIR)/$(APP_NAME).zip \
		--keychain-profile "$(NOTARY_PROFILE)" --wait
	@xcrun stapler staple $(APP_BUNDLE)
	@rm -f $(BUILD_DIR)/$(APP_NAME).zip
	@echo "Notarized and stapled $(APP_BUNDLE)"

test: $(BUILD_DIR)/$(TEST_NAME)
	$(BUILD_DIR)/$(TEST_NAME)

# Fast lane: unit + viewmodel + safety tests only (no fixtures, <5s)
test-fast: $(BUILD_DIR)/$(TEST_NAME)
	$(BUILD_DIR)/$(TEST_NAME) --filter "PageRangeParser|PDFCompressor|PDFSplitter|PDFConcatenator|PDFRotator|PDFCropper|PDFMetadataEditor|PDFColorAdjuster|PDFFileItem|Utilities|AppViewModel|CompressViewModel|SplitViewModel|ConcatenateViewModel|SourceEqualsDestination|Failure Modes|End-to-End|PDFImageExporter|PDFImageConverter"

# Corpus lane: all fixture-based tests (requires PDFs in Fixtures/)
test-corpus: $(BUILD_DIR)/$(TEST_NAME)
	$(BUILD_DIR)/$(TEST_NAME) --filter "Fixture|Invariant|Visual|Performance|Differential|Cancellation|Safety"

$(BUILD_DIR)/$(TEST_NAME): $(TESTABLE_SOURCES) $(TEST_SOURCES)
	@mkdir -p $(BUILD_DIR)
	swiftc -target $(TARGET) -sdk $(SDK) -parse-as-library \
		-framework PDFKit -framework AppKit -framework Foundation \
		-F $(TESTING_FW_DIR) \
		-framework Testing \
		-Xlinker -rpath -Xlinker $(TESTING_FW_DIR) \
		-Xlinker -rpath -Xlinker $(TESTING_RPATH_DIR) \
		-load-plugin-library $(TESTING_PLUGIN) \
		-module-name PDFwringer \
		-o $@ \
		$(TESTABLE_SOURCES) $(TEST_SOURCES)

release: SWIFT_FLAGS += $(RELEASE_FLAGS)
release: clean build app sign
	@echo "Release build ready at $(APP_BUNDLE)"

dmg: release
	@rm -rf $(BUILD_DIR)/dmg_staging $(BUILD_DIR)/$(APP_NAME).dmg
	@mkdir -p $(BUILD_DIR)/dmg_staging
	@cp -R $(APP_BUNDLE) $(BUILD_DIR)/dmg_staging/
	@ln -s /Applications $(BUILD_DIR)/dmg_staging/Applications
	@hdiutil create -volname "$(APP_NAME)" -srcfolder $(BUILD_DIR)/dmg_staging \
		-ov -format UDRW $(BUILD_DIR)/$(APP_NAME)_rw.dmg >/dev/null
	@hdiutil attach $(BUILD_DIR)/$(APP_NAME)_rw.dmg >/dev/null
	@osascript scripts/dmg_layout.applescript
	@sync && sleep 1
	@chflags nohidden /Volumes/$(APP_NAME)/$(APP_NAME).app
	@xattr -d com.apple.FinderInfo /Volumes/$(APP_NAME)/$(APP_NAME).app 2>/dev/null || true
	@hdiutil detach /Volumes/$(APP_NAME) >/dev/null
	@hdiutil convert $(BUILD_DIR)/$(APP_NAME)_rw.dmg -format UDZO \
		-o $(BUILD_DIR)/$(APP_NAME).dmg >/dev/null
	@rm -rf $(BUILD_DIR)/dmg_staging $(BUILD_DIR)/$(APP_NAME)_rw.dmg
	@echo "Submitting DMG for notarization..."
	@xcrun notarytool submit $(BUILD_DIR)/$(APP_NAME).dmg \
		--keychain-profile "$(NOTARY_PROFILE)" --wait
	@xcrun stapler staple $(BUILD_DIR)/$(APP_NAME).dmg
	@echo "Built and notarized $(BUILD_DIR)/$(APP_NAME).dmg"

clean:
	rm -rf $(BUILD_DIR)

run: build
	$(BUILD_DIR)/$(APP_NAME)
