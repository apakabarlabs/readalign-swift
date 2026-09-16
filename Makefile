.PHONY: build test test-build docs lint lint-fix format clean install

build:
	swift build

test:
	swift test

test-build:
	swift build --build-tests

docs:
	swift package --allow-writing-to-directory .build/docc generate-documentation \
		--target ReadAlign --output-path .build/docc \
		--warnings-as-errors \
		--transform-for-static-hosting \
		--hosting-base-path readalign-swift

lint:
	swiftlint --strict

lint-fix:
	swiftlint --fix

format:
	swift-format -i -r Sources Tests

clean:
	swift package clean
	rm -rf .build

install:
	brew install swiftlint swift-format
