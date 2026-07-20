SDK := $(shell xcrun --show-sdk-path)
TARGET := arm64-apple-macosx26.0
SWIFT_LANGUAGE_FLAGS := -swift-version 6 -strict-concurrency=complete
SWIFT_FLAGS := -target $(TARGET) -sdk $(SDK) $(SWIFT_LANGUAGE_FLAGS) -parse-as-library -framework SwiftUI -framework PDFKit -framework AppKit
RELEASE_FLAGS := -O -whole-module-optimization
VERSION := $(shell git describe --tags --abbrev=0 2>/dev/null | sed 's/^v//')
ifeq ($(VERSION),)
    VERSION := 0.0.0
endif
SIGN_IDENTITY := Developer ID Application: Lukas N.P. Egger (7DGU3C2XRL)
ENTITLEMENTS := PDFwringer/PDFwringer.entitlements
NOTARY_PROFILE := notarytool-profile
SOURCES := $(shell find PDFwringer -name '*.swift' | LC_ALL=C sort)
TEST_SOURCES := $(shell find PDFwringerTests -name '*.swift' | LC_ALL=C sort)
TESTABLE_SOURCES := $(shell find PDFwringer/Services PDFwringer/Models PDFwringer/Utilities PDFwringer/ViewModels -name '*.swift' | LC_ALL=C sort)
BUILD_DIR := .build
APP_NAME := PDFwringer
APP_BUNDLE := $(BUILD_DIR)/$(APP_NAME).app
TEST_NAME := PDFwringerTests
APP_SOURCE_LIST := $(BUILD_DIR)/app-sources.list
TEST_SOURCE_LIST := $(BUILD_DIR)/test-sources.list
FIXTURE_CHECKSUMS := PDFwringerTests/Fixtures/SHA256SUMS
FAST_TEST_FILTER := AppViewModelTests|AtomicWriteSafetyTests|CancellationContractTests|CompressViewModelTests|ConcatenateViewModelTests|EncryptedWorkflowTests|EndToEndTests|FailureModeTests|PDFColorAdjusterTests|PDFCompressorTests|PDFConcatenatorTests|PDFCropperTests|PDFFileItemTests|PDFImageConverterTests|PDFImageExporterTests|PDFMetadataEditorTests|PDFRotatorTests|PDFSplitterTests|PageRangeParserTests|PageSelectionTests|PathEdgeCaseTests|SourceEqualsDestinationTests|SplitViewModelTests|UtilityTests|ViewModelLifecycleTests
CORPUS_TEST_FILTER := DifferentialEquivalenceTests|Fixture.*Tests|PageGeometryTests|PerformanceBoundsTests|TextPreservationTests|VisualRegressionTests

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

.PHONY: build clean run test test-fast test-corpus verify-fixtures app release dmg sign notarize FORCE

FORCE:

$(APP_SOURCE_LIST): FORCE
	@mkdir -p $(BUILD_DIR)
	@printf '%s\n' $(SOURCES) > $@.tmp
	@if ! cmp -s $@.tmp $@; then mv $@.tmp $@; else rm $@.tmp; fi

$(TEST_SOURCE_LIST): FORCE
	@mkdir -p $(BUILD_DIR)
	@printf '%s\n' $(TESTABLE_SOURCES) $(TEST_SOURCES) > $@.tmp
	@if ! cmp -s $@.tmp $@; then mv $@.tmp $@; else rm $@.tmp; fi

build: $(BUILD_DIR)/$(APP_NAME)

$(BUILD_DIR)/$(APP_NAME): Makefile $(APP_SOURCE_LIST) $(SOURCES)
	@mkdir -p $(BUILD_DIR)
	swiftc $(SWIFT_FLAGS) -o $@ $(SOURCES)

app: $(APP_BUNDLE)

$(APP_BUNDLE): Makefile $(BUILD_DIR)/$(APP_NAME) $(ENTITLEMENTS) PDFwringer/Resources/AppIcon.icns
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

test: verify-fixtures $(BUILD_DIR)/$(TEST_NAME)
	$(BUILD_DIR)/$(TEST_NAME)

# Fast lane: unit + viewmodel + safety tests only (no fixtures, <5s)
test-fast: $(BUILD_DIR)/$(TEST_NAME)
	$(BUILD_DIR)/$(TEST_NAME) --filter "$(FAST_TEST_FILTER)"

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

$(BUILD_DIR)/$(TEST_NAME): Makefile $(TEST_SOURCE_LIST) $(TESTABLE_SOURCES) $(TEST_SOURCES)
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
