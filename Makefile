.PHONY: build test inspect plan clean

build:
	swift build -c release

test:
	swift run wechatguard-tests

inspect:
	swift run wechatguard inspect

plan:
	swift run wechatguard plan

clean:
	swift package clean
