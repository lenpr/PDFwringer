SDK := $(shell xcrun --show-sdk-path)
TARGET := arm64-apple-macosx26.0
SWIFT_FLAGS := -target $(TARGET) -sdk $(SDK) -parse-as-library -framework SwiftUI -framework PDFKit -framework AppKit
SOURCES := $(shell find PDFwringer -name '*.swift')
TEST_SOURCES := $(shell find PDFwringerTests -name '*.swift')
TESTABLE_SOURCES := $(shell find PDFwringer/Services PDFwringer/Models PDFwringer/Utilities -name '*.swift')
BUILD_DIR := .build
APP_NAME := PDFwringer
TEST_NAME := PDFwringerTests

.PHONY: build clean run test

build: $(BUILD_DIR)/$(APP_NAME)

$(BUILD_DIR)/$(APP_NAME): $(SOURCES)
	@mkdir -p $(BUILD_DIR)
	swiftc $(SWIFT_FLAGS) -o $@ $(SOURCES)

test: $(BUILD_DIR)/$(TEST_NAME)
	$(BUILD_DIR)/$(TEST_NAME)

$(BUILD_DIR)/$(TEST_NAME): $(TESTABLE_SOURCES) $(TEST_SOURCES)
	@mkdir -p $(BUILD_DIR)
	swiftc -target $(TARGET) -sdk $(SDK) -parse-as-library \
		-framework PDFKit -framework AppKit -framework Foundation \
		-F /Library/Developer/CommandLineTools/Library/Developer/Frameworks \
		-framework Testing \
		-Xlinker -rpath -Xlinker /Library/Developer/CommandLineTools/Library/Developer/Frameworks \
		-Xlinker -rpath -Xlinker /Library/Developer/CommandLineTools/Library/Developer/usr/lib \
		-load-plugin-library /Library/Developer/CommandLineTools/usr/lib/swift/host/plugins/testing/libTestingMacros.dylib \
		-module-name PDFwringer \
		-o $@ \
		$(TESTABLE_SOURCES) $(TEST_SOURCES)

clean:
	rm -rf $(BUILD_DIR)

run: build
	$(BUILD_DIR)/$(APP_NAME)
