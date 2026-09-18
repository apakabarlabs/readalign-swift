COMMENTCENSOR_VERSION ?= v0.3.2
COMMENTCENSOR_ENV = .build/commentcensor
COMMENTCENSOR = $(COMMENTCENSOR_ENV)/bin/commentcensor

.DEFAULT_GOAL := build

.PHONY: install-tools format comments lint test-build test docs build clean install

install-tools:
	brew install swiftlint swift-format
	python3 -m venv $(COMMENTCENSOR_ENV)
	$(COMMENTCENSOR_ENV)/bin/pip install --quiet --upgrade git+https://github.com/botforge-pro/commentcensor.git@$(COMMENTCENSOR_VERSION)

format:
	swift-format -i -r Sources Tests

comments:
	$(COMMENTCENSOR) .

lint: comments
	swiftlint --strict

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
	swiftlint --fix

build: lint test-build test docs
	swift build

clean:
	swift package clean
	rm -rf .build

install:
	$(MAKE) install-tools
