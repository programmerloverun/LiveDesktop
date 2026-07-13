APP_NAME       := LiveDesktop
BUNDLE_NAME    := LiveDesktop.app
BUNDLE_ID      := com.livedesktop.app
VERSION        := 1.1.0
BUILD_DIR      := .build
DMG_NAME       := LiveDesktop-$(VERSION).dmg

# Signing (fill these in before running `make release`)
DEV_ID         ?= # e.g. "Developer ID Application: Your Name (TEAMID)"
APPLE_ID       ?= # your Apple ID email
TEAM_ID        ?= # your Team ID
APP_PASSWORD   ?= # app-specific password for notarization
KEYCHAIN_PROFILE ?= notarytool-profile

.PHONY: build app sign notarize staple dmg release clean

# ── Build ────────────────────────────────────────────
build:
	swift build -c release

app: build
	rm -rf "$(BUILD_DIR)/$(BUNDLE_NAME)"
	mkdir -p "$(BUILD_DIR)/$(BUNDLE_NAME)/Contents/MacOS"
	mkdir -p "$(BUILD_DIR)/$(BUNDLE_NAME)/Contents/Resources"
	cp $(BUILD_DIR)/release/$(APP_NAME) "$(BUILD_DIR)/$(BUNDLE_NAME)/Contents/MacOS/"
	cp $(APP_NAME).icns "$(BUILD_DIR)/$(BUNDLE_NAME)/Contents/Resources/AppIcon.icns"
	cp Sources/title-icon.png "$(BUILD_DIR)/$(BUNDLE_NAME)/Contents/Resources/title-icon.png"
	cp -R Resources/BuiltInWallpapers "$(BUILD_DIR)/$(BUNDLE_NAME)/Contents/Resources/"
	sed -e 's/__VERSION__/$(VERSION)/g' \
	    -e 's/__BUNDLE_ID__/$(BUNDLE_ID)/g' \
	    packaging/Info.plist.template > "$(BUILD_DIR)/$(BUNDLE_NAME)/Contents/Info.plist"
	echo "APPL????" > "$(BUILD_DIR)/$(BUNDLE_NAME)/Contents/PkgInfo"
	@echo "App built: $(BUILD_DIR)/$(BUNDLE_NAME)"

# ── Code Sign ─────────────────────────────────────────
sign: app
ifndef DEV_ID
	$(error "Set DEV_ID first, e.g.: make sign DEV_ID='Developer ID Application: ...'")
endif
	codesign --deep --force --verify --verbose \
		--options runtime \
		--timestamp \
		--entitlements packaging/entitlements.plist \
		--sign "$(DEV_ID)" \
		"$(BUILD_DIR)/$(BUNDLE_NAME)"
	codesign -vvv "$(BUILD_DIR)/$(BUNDLE_NAME)"

# ── Notarize ─────────────────────────────────────────
notarize: sign
ifndef APPLE_ID
	$(error "Set APPLE_ID, TEAM_ID, APP_PASSWORD first")
endif
	@# Create zip for notarization
	cd $(BUILD_DIR) && ditto -c -k --keepParent "$(BUNDLE_NAME)" notarize.zip
	xcrun notarytool submit "$(BUILD_DIR)/notarize.zip" \
		--apple-id "$(APPLE_ID)" \
		--team-id "$(TEAM_ID)" \
		--password "$(APP_PASSWORD)" \
		--wait
	@rm -f "$(BUILD_DIR)/notarize.zip"

# ── Staple ───────────────────────────────────────────
staple:
	xcrun stapler staple "$(BUILD_DIR)/$(BUNDLE_NAME)"
	@echo "Notarization ticket stapled."

# ── DMG ──────────────────────────────────────────────
dmg: staple
	rm -f "$(BUILD_DIR)/$(DMG_NAME)"
	chmod +x packaging/create-dmg.sh
	packaging/create-dmg.sh "$(BUILD_DIR)/$(BUNDLE_NAME)" "$(BUILD_DIR)/$(DMG_NAME)"

# ── Full Release Pipeline ────────────────────────────
release: build sign notarize staple dmg
	@echo ""
	@echo "========================================="
	@echo "  Release package: $(BUILD_DIR)/$(DMG_NAME)"
	@echo "========================================="

# ── Clean ────────────────────────────────────────────
clean:
	rm -rf $(BUILD_DIR)
	swift package clean 2>/dev/null || true
