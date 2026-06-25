targets := main test

main:
	zig build main
test:
	zig build test

dev:
	make dev_main
dev_main:
	zig build main --watch
dev_test:
	zig build test --watch --fincremental