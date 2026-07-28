.PHONY: build test coverage app dmg install-local inspect plan doctor verify-version homebrew-audit homebrew-smoke clean

APP ?= /Applications/WeChat.app

build:
	swift build -c release

test:
	swift run ihavealreadyseenit-tests

coverage:
	scripts/coverage.sh

app:
	scripts/package-app.sh

dmg:
	scripts/package-dmg.sh

install-local:
	scripts/install-local.sh

inspect:
	swift run ihavealreadyseenit inspect

plan:
	swift run ihavealreadyseenit plan

doctor:
	swift run ihavealreadyseenit doctor

verify-version:
	swift run ihavealreadyseenit verify-version --app "$(APP)"

homebrew-audit:
	scripts/verify-homebrew-cask.sh

homebrew-smoke:
	scripts/test-homebrew-cask.sh

clean:
	swift package clean
