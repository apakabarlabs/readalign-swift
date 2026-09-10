.PHONY: build test test-build lint lint-fix format clean install

build:
	swift build

test:
	swift test

test-build:
	swift build --build-tests

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
