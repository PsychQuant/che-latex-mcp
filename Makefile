BINARY_NAME := che-latex-mcp
VERSION := $(shell grep -E 'version: "' Sources/che-latex-mcp/LatexMCPApp.swift | head -1 | sed -E 's/.*"([^"]+)".*/\1/')

.PHONY: build release release-universal install install-signed sign notarize release-signed release-github clean test help

help:
	@echo "che-latex-mcp Makefile targets:"
	@echo "  build           — dev build (debug)"
	@echo "  release         — release build (single arch)"
	@echo "  release-universal — universal release build (arm64 + x86_64)"
	@echo "  install         — local install with ad-hoc signing (~/bin/$(BINARY_NAME))"
	@echo "  install-signed  — local install with Developer ID (no notarization)"
	@echo "  sign            — codesign universal binary with Developer ID"
	@echo "  notarize        — submit signed binary to Apple notarytool"
	@echo "  release-signed  — full release pipeline: universal → sign → notarize → release-artifacts/"
	@echo "  release-github  — upload release-artifacts/ to GitHub Release v$(VERSION)"
	@echo "  clean           — swift package clean + remove release artifacts"
	@echo "  test            — swift test"
	@echo ""
	@echo "Current version (from LatexMCPApp.swift): $(VERSION)"

build:
	swift build

release:
	swift build -c release

# Universal binary (arm64 + x86_64) for distribution.
release-universal:
	swift build -c release --arch arm64 --arch x86_64

# Local dev install with ad-hoc signing. Fast iteration.
install: release
	rm -f ~/bin/$(BINARY_NAME)
	cp .build/release/$(BINARY_NAME) ~/bin/$(BINARY_NAME)
	chmod +x ~/bin/$(BINARY_NAME)
	codesign --force --sign - ~/bin/$(BINARY_NAME)
	@echo "✓ Installed ~/bin/$(BINARY_NAME) (ad-hoc signed — dev only)"

# Local install with Developer ID (no notarization). Suitable for dev iteration
# on machines that need real signature (e.g. macOS 26 TCC dialogs).
install-signed: release
	@: $${DEVELOPER_ID:?DEVELOPER_ID not set. See CLAUDE.md Apple Developer section}
	rm -f ~/bin/$(BINARY_NAME)
	cp .build/release/$(BINARY_NAME) ~/bin/$(BINARY_NAME)
	chmod +x ~/bin/$(BINARY_NAME)
	codesign --force --sign "$$DEVELOPER_ID" --options runtime --timestamp ~/bin/$(BINARY_NAME)
	@echo "✓ Installed ~/bin/$(BINARY_NAME) (Developer ID signed, NOT notarized)"

# Codesign the universal binary with Developer ID + hardened runtime.
sign: release-universal
	@: $${DEVELOPER_ID:?DEVELOPER_ID not set. See CLAUDE.md Apple Developer section}
	@BINARY_PATH=".build/apple/Products/Release/$(BINARY_NAME)"; \
	if [ ! -f "$$BINARY_PATH" ]; then \
		BINARY_PATH=".build/release/$(BINARY_NAME)"; \
	fi; \
	codesign --force --sign "$$DEVELOPER_ID" --options runtime --timestamp "$$BINARY_PATH"; \
	echo "✓ Signed $$BINARY_PATH with Developer ID"

# Notarize signed binary via xcrun notarytool.
# Apple round-trip ~2-10 min.
notarize: sign
	@: $${NOTARY_PROFILE:?NOTARY_PROFILE not set. See CLAUDE.md Apple Developer section}
	@BINARY_PATH=".build/apple/Products/Release/$(BINARY_NAME)"; \
	if [ ! -f "$$BINARY_PATH" ]; then \
		BINARY_PATH=".build/release/$(BINARY_NAME)"; \
	fi; \
	ZIP_PATH="/tmp/$(BINARY_NAME)-$(VERSION).zip"; \
	ditto -c -k --keepParent "$$BINARY_PATH" "$$ZIP_PATH"; \
	echo "Submitting $$ZIP_PATH to Apple notarytool (this can take 2-10 minutes)..."; \
	xcrun notarytool submit "$$ZIP_PATH" --keychain-profile "$$NOTARY_PROFILE" --wait; \
	rm -f "$$ZIP_PATH"; \
	echo "✓ Notarization complete"

# Full distribution release: universal build → sign → notarize → copy to release-artifacts/.
# Resulting binary at release-artifacts/$(BINARY_NAME) is ready to upload to GitHub Release.
release-signed: notarize
	@mkdir -p release-artifacts
	@BINARY_PATH=".build/apple/Products/Release/$(BINARY_NAME)"; \
	if [ ! -f "$$BINARY_PATH" ]; then \
		BINARY_PATH=".build/release/$(BINARY_NAME)"; \
	fi; \
	cp "$$BINARY_PATH" "release-artifacts/$(BINARY_NAME)"; \
	cd release-artifacts && shasum -a 256 $(BINARY_NAME) > $(BINARY_NAME).sha256; \
	echo ""; \
	echo "✓ Release artifact ready:"; \
	echo "    release-artifacts/$(BINARY_NAME)"; \
	echo "    release-artifacts/$(BINARY_NAME).sha256"; \
	echo ""; \
	echo "Next steps:"; \
	echo "    1. git tag v$(VERSION) && git push origin v$(VERSION)"; \
	echo "    2. make release-github     # uploads to GitHub Release"; \
	echo "    3. cd ~/Developer/psychquant-claude-plugins && /plugin-update che-latex-mcp"

# Upload release-artifacts/ to GitHub Release v$(VERSION).
# Requires gh CLI configured.
release-github:
	@if [ ! -f "release-artifacts/$(BINARY_NAME)" ]; then \
		echo "❌ release-artifacts/$(BINARY_NAME) not found. Run 'make release-signed' first."; \
		exit 1; \
	fi
	@if ! git rev-parse "v$(VERSION)" >/dev/null 2>&1; then \
		echo "❌ Tag v$(VERSION) does not exist. Run 'git tag v$(VERSION) && git push origin v$(VERSION)' first."; \
		exit 1; \
	fi
	gh release create "v$(VERSION)" \
		release-artifacts/$(BINARY_NAME) \
		release-artifacts/$(BINARY_NAME).sha256 \
		--title "v$(VERSION)" \
		--notes-file CHANGELOG.md || \
	gh release upload "v$(VERSION)" \
		release-artifacts/$(BINARY_NAME) \
		release-artifacts/$(BINARY_NAME).sha256 \
		--clobber
	@echo "✓ Uploaded to https://github.com/kiki830621/che-latex-mcp/releases/tag/v$(VERSION)"

test:
	swift test

clean:
	swift package clean
	rm -rf release-artifacts
	rm -f /tmp/$(BINARY_NAME)-*.zip
