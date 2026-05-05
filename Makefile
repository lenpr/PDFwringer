SDK := $(shell xcrun --show-sdk-path)
TARGET := arm64-apple-macosx26.0
SWIFT_FLAGS := -target $(TARGET) -sdk $(SDK) -parse-as-library -framework SwiftUI -framework PDFKit -framework AppKit
SOURCES := $(shell find PDFwringer -name '*.swift')
BUILD_DIR := .build
APP_NAME := PDFwringer

.PHONY: build clean run

build: $(BUILD_DIR)/$(APP_NAME)

$(BUILD_DIR)/$(APP_NAME): $(SOURCES)
	@mkdir -p $(BUILD_DIR)
	swiftc $(SWIFT_FLAGS) -o $@ $(SOURCES)

clean:
	rm -rf $(BUILD_DIR)

run: build
	$(BUILD_DIR)/$(APP_NAME)
