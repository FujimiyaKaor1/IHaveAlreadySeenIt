.PHONY: build test coverage app inspect plan doctor clean

build:
	swift build -c release

test:
	swift run ihavealreadyseenit-tests

coverage:
	scripts/coverage.sh

app:
	scripts/package-app.sh

inspect:
	swift run ihavealreadyseenit inspect

plan:
	swift run ihavealreadyseenit plan

doctor:
	swift run ihavealreadyseenit doctor

clean:
	swift package clean
