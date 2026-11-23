CC = clang
CFLAGS = -fobjc-arc -O2 -Wall -Wno-deprecated-declarations -mmacosx-version-min=13.0 -arch arm64 -arch x86_64
FRAMEWORKS = -framework Cocoa -framework AVFoundation -framework AudioToolbox -framework QuartzCore -framework ApplicationServices -framework ServiceManagement -framework Carbon

APP_NAME = Clackity
VERSION = 1.0.0
BUILD_DIR = build.noindex
APP_BUNDLE = $(BUILD_DIR)/$(APP_NAME).app
CONTENTS_DIR = $(APP_BUNDLE)/Contents
MACOS_DIR = $(CONTENTS_DIR)/MacOS
RESOURCES_DIR = $(CONTENTS_DIR)/Resources

SRCS = src/main.m \
       src/AppDelegate.m \
       src/AudioEngine.m \
       src/SoundSynthesizer.m \
       src/SoundPackManager.m \
       src/CommunitySoundPacks.m \
       src/InputMonitor.m \
       src/RippleOverlay.m \
       src/MenuBarController.m \
       src/UpdateManager.m \
       src/SettingsWindowController.m

OBJS = $(patsubst src/%.m, $(BUILD_DIR)/obj/%.o, $(SRCS))

PKG_NAME = Clackity-Installer.pkg
PKG_PATH = $(BUILD_DIR)/$(PKG_NAME)
ZIP_NAME = Clackity-macOS.zip
ZIP_PATH = $(BUILD_DIR)/$(ZIP_NAME)
ROOT_DIR = $(BUILD_DIR)/pkg_root

.PHONY: all clean app run pkg zip dist install

all: app

app: $(APP_BUNDLE)

$(BUILD_DIR)/obj/%.o: src/%.m
	@mkdir -p $(BUILD_DIR)/obj
	@echo "==> Compiling $<..."
	@$(CC) $(CFLAGS) -c $< -o $@

$(APP_BUNDLE): $(OBJS) Resources/Info.plist
	@mkdir -p $(MACOS_DIR)
	@mkdir -p $(RESOURCES_DIR)
	@touch $(BUILD_DIR)/.metadata_never_index
	@echo "==> Linking native Clackity binary..."
	@$(CC) $(CFLAGS) $(FRAMEWORKS) $(OBJS) -o $(MACOS_DIR)/$(APP_NAME)
	@echo "==> Copying Info.plist and Resources..."
	@cp Resources/Info.plist $(CONTENTS_DIR)/Info.plist
	@cp Resources/AppIcon.icns $(RESOURCES_DIR)/AppIcon.icns
	@cp Resources/MenuBarIcon*.png $(RESOURCES_DIR)/
	@cp -R Resources/SoundPacks $(RESOURCES_DIR)/ 2>/dev/null || true
	@cp -R Resources/Previews $(RESOURCES_DIR)/ 2>/dev/null || true
	@cp Resources/community_soundpacks.json $(RESOURCES_DIR)/ 2>/dev/null || true
	@echo "==> Applying persistent identifier code signature..."
	@codesign -s - --force --deep --identifier "com.jojoyboy.Clackity" -r='designated => identifier "com.jojoyboy.Clackity"' $(APP_BUNDLE)
	@/System/Library/Frameworks/CoreServices.framework/Frameworks/LaunchServices.framework/Support/lsregister -u $(APP_BUNDLE) 2>/dev/null || true
	@echo "==> Successfully created $(APP_BUNDLE)"

zip: app
	@echo "==> Creating macOS application zip archive..."
	@ditto -c -k --keepParent $(APP_BUNDLE) $(ZIP_PATH)
	@echo "==> Successfully created $(ZIP_PATH)"

pkg: app zip
	@echo "==> Packaging macOS installer (.pkg)..."
	@rm -rf $(ROOT_DIR)
	@mkdir -p $(ROOT_DIR)/Applications
	@cp -R $(APP_BUNDLE) $(ROOT_DIR)/Applications/
	@chmod +x pkg_scripts/postinstall 2>/dev/null || true
	@pkgbuild --root $(ROOT_DIR) --scripts pkg_scripts --identifier com.jojoyboy.Clackity --version $(VERSION) $(PKG_PATH)
	@rm -rf $(ROOT_DIR)
	@echo "==> Successfully created $(PKG_PATH)"

dist: pkg zip

install: app
	@echo "==> Installing Clackity to /Applications..."
	@pkill -x $(APP_NAME) 2>/dev/null || true
	@rm -rf /Applications/$(APP_NAME).app
	@cp -R $(APP_BUNDLE) /Applications/$(APP_NAME).app
	@codesign -s - --force --deep --identifier "com.jojoyboy.Clackity" -r='designated => identifier "com.jojoyboy.Clackity"' /Applications/$(APP_NAME).app
	@touch /Applications/$(APP_NAME).app
	@/System/Library/Frameworks/CoreServices.framework/Frameworks/LaunchServices.framework/Support/lsregister -u $(APP_BUNDLE) 2>/dev/null || true
	@/System/Library/Frameworks/CoreServices.framework/Frameworks/LaunchServices.framework/Support/lsregister -f /Applications/$(APP_NAME).app 2>/dev/null || true
	@rm -rf $(APP_BUNDLE)
	@echo "==> Successfully installed single instance to /Applications/$(APP_NAME).app"

run: install
	@echo "==> Launching /Applications/$(APP_NAME).app..."
	open /Applications/$(APP_NAME).app

clean:
	@/System/Library/Frameworks/CoreServices.framework/Frameworks/LaunchServices.framework/Support/lsregister -u $(APP_BUNDLE) 2>/dev/null || true
	@rm -rf $(BUILD_DIR) build
	@echo "==> Cleaned build directory"
