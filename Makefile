.DEFAULT_GOAL := build

.PHONY: install-tools format comments lint test-build test docs build clean install sync-yaml

sync-yaml:
	mkdir -p ../readalign-kotlin/src/main/resources/fm/apakabar/readalign ../readalign-kotlin/src/test/resources
	cp Sources/ReadAlign/Resources/rules.yaml ../readalign-kotlin/src/main/resources/fm/apakabar/readalign/
	cp Tests/ReadAlignTests/Resources/*.yaml ../readalign-kotlin/src/test/resources/
	cp Sources/ReadAlign/Resources/rules.yaml ../readalign-python/readalign/rules.yaml
	cp Tests/ReadAlignTests/Resources/*.yaml ../readalign-python/tests/cases/

install-tools:
	brew install swiftlint swift-format
	python3 -m pip install --quiet --upgrade git+https://github.com/botforge-pro/commentcensor.git

format:
	swift-format format --in-place --recursive Sources Tests Package.swift

comments:
	commentcensor .

lint: comments
	swiftlint --strict
	swift-format lint --strict --recursive Sources Tests Package.swift

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

lint-fix:
	$(MAKE) format

build: lint test-build test docs
	swift build

clean:
	swift package clean
	rm -rf .build

install:
	$(MAKE) install-tools
