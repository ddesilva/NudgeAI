# Nudge AI build targets. Local dev → `make dev`. Public release → `make release`.

# Pulls DEVELOPER_ID (and any other per-developer overrides) from a local,
# gitignored file. See Makefile.local.example for the template.
-include Makefile.local
VERSION := $(shell /usr/libexec/PlistBuddy -c 'Print CFBundleShortVersionString' Info.plist)
DMG := NudgeAI-$(VERSION).dmg

.PHONY: dev release dry-run publish clean

dev:
	./build.sh debug

release:
	DEVELOPER_ID="$(DEVELOPER_ID)" ./release.sh

dry-run:
	SKIP_NOTARIZE=1 DEVELOPER_ID="$(DEVELOPER_ID)" ./release.sh

# Cut a GitHub release for the current version and attach the DMG.
# Requires: gh CLI authed, $(DMG) already built (run `make release` first),
# and a clean working tree at the commit you want to ship.
publish:
	@[ -f "$(DMG)" ] || (echo "Missing $(DMG) — run 'make release' first." && exit 1)
	git tag -a v$(VERSION) -m "Nudge AI $(VERSION)" || true
	git push origin v$(VERSION)
	gh release create v$(VERSION) "$(DMG)" \
		--title "Nudge AI $(VERSION)" \
		--generate-notes

clean:
	rm -rf .build NudgeAI.app NudgeAI-*.dmg NudgeAI-*.zip
