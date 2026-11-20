XCODEBUILD_ARGS ?=

all: configure clean lint test package

configure: Signing.xcconfig Version.xcconfig .git/hooks/pre-commit

configure-release: configure Release.xcconfig

Signing.xcconfig:
	@./Scripts/configure-code-signing

Version.xcconfig:
	@./Scripts/configure-version

Release.xcconfig:
	@./Scripts/configure-release

.git/hooks/pre-commit:
	cp ./Scripts/pre-commit $@

clean:
	rm -fr build

lint:
	swiftformat --lint .
	swiftlint .

test: hidpp-test gesturekit-test dockkit-test pointerkit-test
	xcodebuild test -project LinearMouse.xcodeproj -scheme LinearMouse $(XCODEBUILD_ARGS)

hidpp-test:
	swift test --package-path Modules/HIDPP

gesturekit-test:
	swift test --package-path Modules/GestureKit

dockkit-test:
	swift test --package-path Modules/DockKit

pointerkit-test:
	swift test --package-path Modules/PointerKit

package:
	@./Scripts/LocalBuild
	@python3 Scripts/PackageDMG.py

prepublish: package
	@./Scripts/sign-and-notarize

.PHONY: all configure test hidpp-test gesturekit-test dockkit-test pointerkit-test build clean package
