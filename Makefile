# Accretion — all commands in one place. `make help` lists them.

PROJECT   := Accretion.xcodeproj
SCHEME    := Accretion
BUNDLE_ID := com.romanitalian.accretion
DERIVED   := build

# Physical devices (cable or Wi‑Fi once "Connect via network" is on in Xcode → Devices). `make devices` lists UDIDs.
IPHONE    ?= 00008110-00080DCC01EB801E
IPAD      ?= 00008103-0002684C22B8A01E
DEVICE    ?= $(IPHONE)
# Simulator used for build/test/run (UDID: names repeat across iOS versions). Default: first available iPhone 17 Pro.
SIM       ?= $(shell xcrun simctl list devices available | grep -m1 'iPhone 17 Pro [^M]' | grep -oE '[0-9A-F-]{36}')
SIM_IPAD  ?= $(shell scripts/resolve_screenshot_sim_udid.sh "iPad Pro 13-inch (M5)")

SIM_DEST    := platform=iOS Simulator,id=$(SIM)
DEVICE_DEST := platform=iOS,id=$(DEVICE)
SIM_APP     := $(DERIVED)/Build/Products/Debug-iphonesimulator/Accretion.app
DEVICE_APP  := $(DERIVED)/Build/Products/Release-iphoneos/Accretion.app
XCB         := xcodebuild -project $(PROJECT) -scheme $(SCHEME) -derivedDataPath $(DERIVED)
ARCHIVE     := $(DERIVED)/Accretion.xcarchive

# App Store screenshots: newest-runtime simulators for the two sizes App Store Connect asks for.
SHOT_IPHONE   ?= iPhone 17 Pro Max
SHOT_IPAD     ?= iPad Pro 13-inch (M5)
SHOT_RUN      ?= screenshots/$(shell date '+%Y-%m-%d_%H-%M')
SHOT_RESULTS  := $(DERIVED)/screenshots
OVERLAY_CONFIG ?= screenshots/text-overlays.json
OVERLAY_FONT_SCALE ?= 1.5

.DEFAULT_GOAL := help

.PHONY: help
help: ## Show this list
	@awk 'BEGIN {FS = ":.*## "} /^[a-zA-Z_-]+:.*## / { printf "  \033[36mmake %-20s\033[0m %s\n", $$1, $$2 } /^##@/ { printf "\n\033[33m%s\033[0m\n", substr($$0, 5) }' $(MAKEFILE_LIST)

##@ Project

.PHONY: gen version bump icon clean
gen: ## Sync VERSION.md into project.yml and regenerate the Xcode project
	@python3 scripts/sync_version.py
	xcodegen generate -q

version: ## Print the current version and build
	@python3 scripts/sync_version.py show

bump: ## Build number +1 in VERSION.md (do before every upload)
	@python3 scripts/sync_version.py bump
	@python3 scripts/sync_version.py show

icon: ## Re-render the app icon
	swift scripts/make-icon.swift Accretion/Assets.xcassets/AppIcon.appiconset/AppIcon.png

clean: ## Remove build output
	rm -rf $(DERIVED)

##@ Build & run

.PHONY: build test ci sim sim-ipad device-build install install-ipad install-all devices
build: gen ## Build for the simulator (Debug)
	$(XCB) -destination '$(SIM_DEST)' build -quiet

test: gen ## Run engine unit tests on the simulator
	@set -o pipefail; $(XCB) -destination '$(SIM_DEST)' -only-testing:AccretionTests test 2>&1 \
		| grep -E 'error:|failed|Executed .* tests|\*\* TEST' | sort -u

ci: test archive ## Unit tests + signed Release archive (what a release needs to pass)
	@echo "CI passed: $$(python3 scripts/sync_version.py show)"

sim: build ## Build, install and launch on the iPhone simulator
	xcrun simctl boot '$(SIM)' 2>/dev/null || true
	@open -a Simulator 2>/dev/null || true # optional: not every Xcode ships Simulator.app
	xcrun simctl install '$(SIM)' $(SIM_APP)
	xcrun simctl launch --terminate-running-process '$(SIM)' $(BUNDLE_ID)

sim-ipad: ## Build, install and launch on the iPad simulator
	$(MAKE) sim SIM='$(SIM_IPAD)'

device-build: gen ## Build signed Release for DEVICE
	$(XCB) -configuration Release -destination '$(DEVICE_DEST)' -allowProvisioningUpdates build -quiet

install: device-build ## Build, install and launch on the iPhone (DEVICE=… for another). Unlock it first.
	xcrun devicectl device install app --device $(DEVICE) $(DEVICE_APP)
	xcrun devicectl device process launch --terminate-existing --device $(DEVICE) $(BUNDLE_ID) || \
		echo "Installed. Launch failed — unlock the device and open Accretion."

install-ipad: ## Build, install and launch on the iPad
	$(MAKE) install DEVICE=$(IPAD)

install-all: ## Install on the iPhone and the iPad
	$(MAKE) install DEVICE=$(IPHONE)
	$(MAKE) install DEVICE=$(IPAD)

devices: ## List connected/paired devices
	xcrun devicectl list devices | grep -v simulated

##@ Release

.PHONY: archive testflight release
archive: gen ## Build a signed App Store archive (local only, nothing is uploaded)
	$(XCB) -configuration Release -destination 'generic/platform=iOS' -archivePath $(ARCHIVE) \
		-allowProvisioningUpdates archive -quiet
	@echo "Archive: $(ARCHIVE) — $$(python3 scripts/sync_version.py show)"

testflight: archive ## Archive and UPLOAD to App Store Connect / TestFlight (needs the app record in ASC)
	xcodebuild -exportArchive -archivePath $(ARCHIVE) -exportOptionsPlist ExportOptions.plist \
		-exportPath $(DERIVED)/export -allowProvisioningUpdates

release: bump test testflight ## Build +1, tests, then upload to TestFlight

##@ Screenshots

.PHONY: screenshots screenshots-framed screenshots-text
screenshots: gen ## App Store screenshots (iPhone 6.9" + iPad 13") → screenshots/<date>/default/
	rm -rf "$(SHOT_RESULTS)"; mkdir -p "$(SHOT_RESULTS)"
	@for dev in iphone ipad; do \
		if [ $$dev = iphone ]; then name="$(SHOT_IPHONE)"; else name="$(SHOT_IPAD)"; fi; \
		udid=$$(scripts/resolve_screenshot_sim_udid.sh "$$name"); \
		test -n "$$udid" || { echo "Simulator '$$name' not found"; exit 1; }; \
		echo "--- $$name ($$udid) ---"; \
		xcrun simctl status_bar "$$udid" override --time 9:41 --batteryState charged --batteryLevel 100 2>/dev/null || true; \
		$(XCB) -destination "platform=iOS Simulator,id=$$udid" -only-testing:AccretionUITests \
			-resultBundlePath "$(SHOT_RESULTS)/$$dev.xcresult" test -quiet || true; \
		xcrun simctl shutdown "$$udid" 2>/dev/null || true; \
		bash scripts/extract_screenshots.sh "$(SHOT_RESULTS)/$$dev.xcresult" $$dev "$(SHOT_RUN)/default/$$dev"; \
	done
	@echo "=== Screenshots in $(SHOT_RUN)/default/{iphone,ipad}/ ==="

screenshots-framed: ## Screenshots + device frames (fastlane frameit) → framed/plain/
	@test -d "$(SHOT_RUN)/default" || $(MAKE) screenshots SHOT_RUN="$(SHOT_RUN)"
	bash scripts/frame_screenshots.sh "$(SHOT_RUN)"

screenshots-text: ## Framed screenshots + marketing captions → framed/texted/ (texts: screenshots/text-overlays.json)
	@ls "$(SHOT_RUN)"/framed/plain/*/*.png >/dev/null 2>&1 || $(MAKE) screenshots-framed SHOT_RUN="$(SHOT_RUN)"
	python3 scripts/overlay_screenshot_texts.py --dir "$(SHOT_RUN)" --config "$(OVERLAY_CONFIG)" \
		--style texted --font-scale $(OVERLAY_FONT_SCALE) --gradient-start "#3A1C71" --gradient-end "#0B1030"

##@ Store (fastlane; credentials in fastlane/.env, see fastlane/.env.example)

FASTLANE := LC_ALL=en_US.UTF-8 LANG=en_US.UTF-8 FASTLANE_SKIP_UPDATE_CHECK=1 FASTLANE_HIDE_CHANGELOG=1 \
	PATH="/opt/homebrew/opt/ruby/bin:$$PATH" bundle exec fastlane
STORE_LOCALES ?= en-US ru
# Newest captioned screenshots run (override: STORE_SHOTS=screenshots/<run>/framed/texted).
STORE_SHOTS ?= $(shell ls -d screenshots/*/framed/texted 2>/dev/null | sort | tail -1)

.PHONY: store-setup store-auth store-check store-screenshots store-create-app store-privacy store-metadata store-submit ship
store-setup: ## Install fastlane gems and create fastlane/.env (once)
	PATH="/opt/homebrew/opt/ruby/bin:$$PATH" bundle install --quiet
	@test -f fastlane/.env || { cp fastlane/.env.example fastlane/.env; echo "Created fastlane/.env — fill in the API key"; }

store-auth: ## Check the App Store Connect API key (read-only)
	@$(FASTLANE) ios auth 2>&1 | grep -v "warning:"

store-check: ## Check the listing: Apple's limits, TODOs, screenshot sizes, URLs
	@python3 scripts/check_metadata.py

store-screenshots: ## Copy the newest captioned screenshots into fastlane/screenshots/<locale>/
	bash scripts/stage_store_screenshots.sh "$(STORE_SHOTS)" $(STORE_LOCALES)

store-create-app: ## ONE TIME, Apple ID + 2FA: create the app record (APP_NAME=… if the name is taken)
	$(FASTLANE) ios create_app

store-privacy: ## ONE TIME, Apple ID + 2FA: App Privacy = "Data not collected"
	$(FASTLANE) ios privacy

store-metadata: store-check ## Upload texts, category, age rating, screenshots (nothing is submitted)
	$(FASTLANE) ios metadata

store-submit: store-check ## SUBMIT the build from VERSION.md for App Review (asks first)
	@printf "Submit Accretion $$(python3 scripts/sync_version.py show) for App Review? [y/N] "; read ok; [ "$$ok" = y ]
	$(FASTLANE) ios submit

ship: ## Full release: build +1, tests, TestFlight upload, listing, review submission (asks first)
	$(MAKE) release
	$(MAKE) store-metadata
	$(MAKE) store-submit

##@ Aliases

.PHONY: t ms mp md mi ss ssf sst
t: test ## = test
ms: sim ## = sim
mp: sim-ipad ## = sim-ipad
md: install ## = install (iPhone)
mi: install-ipad ## = install-ipad
ss: screenshots ## = screenshots
ssf: screenshots-framed ## = screenshots-framed
sst: screenshots-text ## = screenshots-text
