
main:
	zig build main
test:
	zig build test
main_dev:
	zig build main --watch --fincremental
test_dev:
	zig build test --watch --fincremental