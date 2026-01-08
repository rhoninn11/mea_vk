#!/bin/bash
PROJ_ROOT="$PWD"

cd vkzig/examples
zig build --watch -fincremental --prominent-compile-errors