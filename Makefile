APP_NAME := Crop
BUILD_DIR := build
APP_BUNDLE := $(BUILD_DIR)/$(APP_NAME).app
SOURCES := $(wildcard Sources/Crop/*.swift)
ARCH := $(shell uname -m)
TARGET := $(ARCH)-apple-macos15.0
SIGN_IDENTITY ?= $(shell security find-identity -p codesigning 2>/dev/null | grep -q "Crop Local Signing" && echo "Crop Local Signing" || echo "-")

.PHONY: all app icon run install clean

all: app

app: $(APP_BUNDLE)

$(APP_BUNDLE): $(SOURCES) Resources/Info.plist $(wildcard Resources/*.lproj/*) Resources/AppIcon.icns Resources/Assets.car
	rm -rf "$(APP_BUNDLE)"
	mkdir -p "$(APP_BUNDLE)/Contents/MacOS" "$(APP_BUNDLE)/Contents/Resources"
	swiftc -O -swift-version 5 -target $(TARGET) \
		-framework AppKit -framework ScreenCaptureKit -framework AVFoundation -framework ServiceManagement \
		$(SOURCES) -o "$(APP_BUNDLE)/Contents/MacOS/$(APP_NAME)"
	cp Resources/Info.plist "$(APP_BUNDLE)/Contents/Info.plist"
	cp Resources/AppIcon.icns Resources/Assets.car "$(APP_BUNDLE)/Contents/Resources/"
	cp -R Resources/*.lproj "$(APP_BUNDLE)/Contents/Resources/"
	codesign --force --sign "$(SIGN_IDENTITY)" "$(APP_BUNDLE)"

icon:
	swift Tools/make-icon.swift Resources/AppIcon.icon/Assets/art.png Resources/logo.png
	rm -rf $(BUILD_DIR)/icon && mkdir -p $(BUILD_DIR)/icon
	xcrun actool Resources/AppIcon.icon --compile $(BUILD_DIR)/icon --platform macosx --minimum-deployment-target 15.0 --app-icon AppIcon --output-partial-info-plist $(BUILD_DIR)/icon/partial.plist
	cp $(BUILD_DIR)/icon/AppIcon.icns Resources/AppIcon.icns
	cp $(BUILD_DIR)/icon/Assets.car Resources/Assets.car

run: app
	open "$(APP_BUNDLE)"

install: app
	rm -rf "/Applications/$(APP_NAME).app"
	cp -R "$(APP_BUNDLE)" "/Applications/$(APP_NAME).app"
	/System/Library/Frameworks/CoreServices.framework/Frameworks/LaunchServices.framework/Support/lsregister -f "/Applications/$(APP_NAME).app"

clean:
	rm -rf "$(BUILD_DIR)"
