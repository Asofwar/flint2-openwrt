SHELL := /bin/sh

.PHONY: build clean verify collect docker-image

build:
	./build.sh

clean:
	./clean.sh

verify:
	./scripts/verify-build.sh

collect:
	./scripts/collect-artifacts.sh

docker-image:
	docker build --tag flint2-openwrt-builder:25.12.5 .

