.PHONY: build test lint lint-fix clean install

build:
	swift build

test:
	swift test

lint:
	swiftlint

lint-fix:
	swiftlint --fix

clean:
	swift package clean
	rm -rf .build Package.resolved

install:
	brew install swiftlint
