#!/bin/bash
PROJ_ROOT="$PWD"

zig build test --watch -fincremental --prominent-compile-errors