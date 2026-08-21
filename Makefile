SHELL := /bin/sh

.PHONY: build build-vm clean verify verify-vm collect docker-image

build:
	./build.sh

build-vm:
	./scripts/build-vm.sh

clean:
	./clean.sh

verify:
	./scripts/verify-build.sh

verify-vm:
	./scripts/verify-vm-build.sh

collect:
	./scripts/collect-artifacts.sh

docker-image:
	docker build --tag flint2-openwrt-builder:25.12.5 .
